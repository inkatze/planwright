# Operator dialogue — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright spends heavily to get a spec right, then hands the operator its
densest moments as if they already held the pipeline's internal model. The
attended human surfaces — beginning with `/spec-kickoff`'s guided dialogue and
sign-off — demand verdicts and hand off identifiers (anchors, lens passes,
REQ/D-IDs, lane names) instead of building understanding. The one skill that
reads as a colleague, `/spec-draft`, is the outlier precisely because it
elicits: it teaches, summarizes, recommends, and interviews. Every other
attended surface talks to a co-processor that is assumed to already hold the
model, not to a peer being brought up to speed.

This spec establishes that at every attended human moment a planwright skill
acts as a **domain expert of the spec that teaches it down to the operator's
level and interviews for exactly what it needs, in-band, and never grades the
spec itself.** Its "opinion" is the skill: judgment lives in the doctrine and
the rigor passes, not in a per-run take on whether the spec is good. This is a
**doctrine-altitude** deliverable by explicit decision (D-1): the operator's
framing that the skills were "made with another bot as an audience, not a peer"
is a doctrine-gap claim, and the fix is one principle the attended surfaces all
inherit, plus its instantiation, not a hand-patch of five skills that would
drift apart again.

Scope is approval-surfaces-first and kickoff-centered (D-9). The work widens
the interaction doctrine past the two authoring skills into three
operationalizable disciplines, instantiates them at `/spec-kickoff`'s sign-off,
fixes the self-contained-confirmation problem the operator hits at every
picker, and is anchored by an on-demand behavioral eval harness so "guides the
operator well" becomes measured rather than a matter of taste.

## Scope

### In scope

- Reworking the `interaction-style` doctrine so it governs every attended human
  surface (not only `/spec-draft` and `/spec-kickoff`), expressed as three
  named disciplines: teach to the frontier, interview to completeness, present
  without steering.
- Instantiating the doctrine at `/spec-kickoff`'s guided dialogue and sign-off,
  in-band, without weakening its existing invariants or colliding with
  `skill-rigor`'s in-flight sign-off verification changes.
- A self-contained-confirmation rule (the decision lives in the option labels;
  explicit equal-weight reject; no pre-selected default) as a doctrine rule and
  a kickoff application.
- Lightweight adaptive-level calibration (teach the frontier, fade), with no
  heavyweight learner model.
- An on-demand behavioral eval harness that drives a skill through a real
  interactive TTY session, driven by simulated-operator personas by expertise,
  grading the artifacts the run writes.
- The measurable-acceptance split: assertable invariants pinned `[test]`;
  experiential quality scored against named rubrics and pilots.
- Instruction-budget compliance (`check:instructions`) for every doctrine and
  skill-prose change this spec makes.

### Out of scope

- `/spec-walkthrough`'s revamp. Deferred, and re-scoped from "adopt the new
  doctrine" to "revisit whether it should exist in this form at all —
  rethink or retire — informed by why it failed" (it shipped out-of-band,
  on-demand-only, and went unused; see Sources). Seeded for a fast-follow.
- The execution-side handoffs (`/orchestrate`, `/execute-task`, `/resume`,
  `/drain`). A second pass, once the pattern proves on kickoff.
- Any weakening of the reserved human controls: never-auto-merge, never
  auto-chain, draft-PR-only, the two-key launch, and the machine-checkable
  sign-off record and content anchor.
- Any verdict, score, or quality assessment of a spec produced by a skill on
  its own behalf: the independence firewall is preserved and reinforced, not
  relaxed.
- Wiring the behavioral evals into CI or `mise run check`: evals stay
  on-demand, consistent with the existing prompt-eval posture.

## REQ-A — The interaction doctrine

- **REQ-A1.1** The `interaction-style` doctrine SHALL govern every attended
  human surface of the pipeline, not only the two authoring skills, so the
  comprehension, approval, handoff, and report moments inherit one stated
  principle.
  *(Cites: D-1; interaction-style doctrine (Sources).)*
- **REQ-A1.2** The doctrine SHALL define three named, operationalizable
  disciplines — *teach to the frontier*, *interview to completeness*, and
  *present without steering* — each stated as inspectable rules rather than a
  tone.
  *(Cites: D-1, D-4, D-5, D-6.)*
- **REQ-A1.3** A skill SHALL cite the doctrine in its manifest for each attended
  human moment it instantiates, so the citation tracks the behavior it governs
  and never precedes it; the cited surface list grows as each surface's behavior
  is reworked (kickoff-first this pass; the execution-side surfaces on their
  deferred pass).
  *(Cites: D-1; instruction-hygiene (Sources).)*
  *(Amended at kickoff 2026-07-17: obligation attached per-surface-at-instantiation so the REQ text matches the kickoff-only verification scope.)*
- **REQ-A1.4** The doctrine's own prose SHALL respect the repo's instruction
  budget: terse and point-of-use, because a skill that front-loads it pays the
  cost against its start-load walls.
  *(Cites: D-10; instruction-headroom (Sources).)*

## REQ-B — Teach to the frontier

- **REQ-B1.1** Comprehension SHALL be built in-band, inside the live dialogue
  where the operator already is, and SHALL NOT depend on a separate out-of-band
  artifact the operator must remember to generate and open.
  *(Cites: D-2; the spec-walkthrough failure (Sources).)*
- **REQ-B1.2** A skill SHALL build its own faithful model of the spec before it
  interviews the operator: comprehend first, then teach and ask.
  *(Cites: D-2.)*
- **REQ-B1.3** The skill SHALL pitch explanation at the operator's frontier —
  skipping what the operator demonstrably already holds, teaching the gap — and
  SHALL fade scaffolding as the operator demonstrates uptake, so a later
  section is not re-explained at the depth of the first.
  *(Cites: D-4; research: ALEKS / Knowledge-Space-Theory, Zone of Proximal Development (Sources).)*
- **REQ-B1.4** Level calibration SHALL be a lightweight running estimate of
  what the operator has picked up, per concept, and SHALL NOT require a
  heavyweight learner model.
  *(Cites: D-4.)*
- **REQ-B1.5** Translating the spec to a lower level SHALL NOT distort it: a
  normative token — MUST, SHALL, SHALL NOT, MAY, a threshold, or an enumerated
  state — is, wherever the explanation conveys that concept, preserved verbatim
  and never softened into vague prose. (This constrains what is conveyed, not
  what must be conveyed: teaching the frontier MAY skip a concept the operator
  already holds, REQ-B1.3; it may never soften one it does present.)
  *(Cites: D-3; spec-comprehension REQ-C1.7 (Sources).)*

## REQ-C — Interview to completeness

- **REQ-C1.1** Elicitation SHALL be goal-directed: the skill SHALL NOT declare
  a section or the sign-off ready while any decision required by the spec's own
  dependency structure is still undefined.
  *(Cites: D-5; research: docassemble backward-chaining (Sources).)*
- **REQ-C1.2** A changed upstream answer SHALL reopen the dependent decisions
  it invalidates, rather than leaving a stale downstream answer standing.
  *(Cites: D-5.)*
- **REQ-C1.3** Questions SHALL be bounded per pass (at most five) and
  asked only when they are actually needed, so the interview converges rather
  than interrogates.
  *(Cites: D-5; research: GitHub Spec Kit /clarify (Sources).)*
- **REQ-C1.4** The skill SHALL carry the clerical weight (deriving candidates,
  formatting, tracking state); the operator SHALL supply judgment, not
  formatting.
  *(Cites: D-1; interaction-style doctrine (Sources).)*
- **REQ-C1.5** The interview SHALL be robust to malformed or unrecognized
  operator input: on input it cannot parse, the skill SHALL re-prompt (restating
  what it needs) rather than advancing the section or the sign-off, and SHALL NOT
  let unparseable input corrupt the running calibration estimate (REQ-B1.4).
  *(Cites: D-4, D-5.)*

## REQ-D — Present without steering

- **REQ-D1.1** A skill SHALL NOT deliver a verdict, score, pass/fail, or
  quality assessment of the spec on its own behalf: the independence firewall
  is preserved.
  *(Cites: D-3; spec-comprehension REQ-D1.1 (Sources).)*
- **REQ-D1.2** The governing line SHALL be information-versus-advice: the skill
  MAY present information *about* the spec — what a decision says, what it
  depends on, the tradeoffs the design already records — but SHALL NOT cross
  into an outcome-driven verdict on whether to approve it.
  *(Cites: D-3; research: legal information-vs-advice (UPL) line (Sources).)*
- **REQ-D1.3** The no-verdict rule SHALL carry an escape valve: it withholds
  the *quality verdict*, never *information the operator asked for*. A mute
  refusal where the operator requested information is a defect, not compliance.
  *(Cites: D-3; research: Khanmigo Socratic-guardrail failure mode (Sources).)*
- **REQ-D1.4** When the skill presents alternatives or a fork, it SHALL apply
  the balance rules — parallel equal-detail presentation, an explicit
  equal-weight reject/do-nothing option, neutralized ordering, and no
  pre-selected default — and SHALL self-audit its own prose against them before
  presenting. The equal-weight / neutralized-ordering / no-recommendation rules
  yield to a *grounded* recommendation (the grounding test, D-12): the skill MAY
  mark a recommended option when its basis is grounded in the spec, the doctrine,
  or mechanical consistency (a reason the operator can verify against the
  artifact); a recommendation resting on the skill's own quality opinion is
  stripped by the self-audit. **No pre-selected default is admissible in any
  case:** a grounded recommendation may be marked and given first with its
  reason, but no option is ever pre-selected as the default — this rule does not
  yield.
  *(Cites: D-6, D-12; research: IPDAS balanced-information standards (Sources).)*
  *(Amended at kickoff 2026-07-17: balance rules carved so a grounded recommendation is the admitted exception; no-pre-selected-default made unconditional.)*
- **REQ-D1.5** Any likelihood the skill surfaces (coverage, confidence, risk)
  SHALL be expressed as a natural frequency with a fixed denominator, never a
  lone percentage or a single one-sided frame.
  *(Cites: D-6; research: IPDAS / CDC Clear Communication Index (Sources).)*

## REQ-E — Self-contained confirmation

This group states the self-contained-confirmation rule, which sits **under**
*present without steering* (REQ-D / D-6): it is a named rule of that discipline,
not a fourth peer discipline. Its "no pre-selected default" is the same
unconditional rule REQ-D1.4 states.

- **REQ-E1.1** Every confirmation SHALL be self-contained in its option set:
  each option restates its own action and its consequence, so the choice is
  answerable from the options alone, without relying on prose rendered above
  the selector (which the operator's terminal may hide).
  *(Cites: D-7; obs:d0753832; research: NN/G confirmation dialogs (Sources).)*
- **REQ-E1.2** A confirmation SHALL include an explicit reject-or-defer option
  at equal prominence and SHALL NOT pre-select a default (unconditionally, the
  same no-default rule as REQ-D1.4; a grounded recommendation may be marked but
  never pre-selected).
  *(Cites: D-7; research: NN/G confirmation dialogs, IPDAS (Sources).)*
- **REQ-E1.3** Generic option labels that force the operator back to unseen
  context — OK, Yes, No, a bare "Approve?" — SHALL NOT be used; the question
  stem SHALL restate in full what is being decided.
  *(Cites: D-7; research: NN/G confirmation dialogs (Sources).)*
- **REQ-E1.4** The operator MAY be offered deeper detail as an in-band layer,
  but the confirmation SHALL remain answerable from the option set alone: the
  deeper layer is supplementary, never load-bearing for the choice.
  *(Cites: D-7; research: progressive disclosure (NN/G) (Sources).)*

## REQ-F — `/spec-kickoff` instantiation

- **REQ-F1.1** `/spec-kickoff`'s guided dialogue SHALL instantiate the three
  disciplines at each section walk and at sign-off, in-band.
  *(Cites: D-9.)*
- **REQ-F1.2** The sign-off moment SHALL present a compact "here is what you
  are about to approve, and what changes downstream when you do" summary that
  builds shared understanding, replacing the bare verdict-demand gate, while
  still leaving the decision to the human.
  *(Cites: D-9; the kickoff sign-off mechanicalness (Sources).)*
- **REQ-F1.3** `/spec-kickoff` SHALL surface its mechanical gates (the lens
  pass, the content anchor, the CI gate) in plain language framed as what they
  protect, not as machine tokens the operator is assumed to already understand.
  *(Cites: D-9.)*
- **REQ-F1.4** The instantiation SHALL NOT weaken `/spec-kickoff`'s existing
  invariants (never-auto-merge, the two-key launch, no-auto-chain, draft-PR-only,
  and the machine-checkable sign-off record and content anchor) and SHALL reconcile
  with `skill-rigor`'s in-flight sign-off verification changes rather than
  colliding with them.
  *(Cites: D-9; skill-rigor (Sources).)*
- **REQ-F1.5** The kickoff prose changes SHALL fit the instruction budget
  (`check:instructions`), trimming or relocating existing prose where the
  additions would otherwise breach it.
  *(Cites: D-10; instruction-headroom (Sources).)*

## REQ-G — Behavioral eval harness

- **REQ-G1.1** The spec SHALL provide an on-demand behavioral eval that drives
  a skill through a real interactive TTY session (not headless `claude -p`), so
  the picker and dialogue surfaces are exercised exactly as the operator sees
  them, sidestepping the headless slash-command injection gap.
  *(Cites: D-8; the headless skill-injection gap (Sources).)*
- **REQ-G1.2** A simulated-operator driver SHALL answer the skill's questions,
  parameterized by an operator-expertise persona (at minimum a domain-novice
  and a domain-expert), so the adaptive-level requirement (REQ-B1.3) is
  behaviorally testable by comparing how the skill pitched to each.
  *(Cites: D-8; REQ-B1.3.)*
- **REQ-G1.3** Grading SHALL read the durable artifacts a run writes (the
  kickoff brief, `tasks.md` state, the sign-off record, a structured
  decision/transcript log the skill emits), NOT a scraped terminal pane; the
  pane is used only for liveness and idle detection.
  *(Cites: D-8.)*
- **REQ-G1.4** The grader SHALL be independent of the driver — a non-Anthropic
  panel backend and/or the human as final rater — so the eval does not collapse
  into the agent grading its own session. If the independent grader is
  unavailable (failure, timeout, rate-limit), the eval SHALL degrade to
  human-rater scoring rather than failing the run, and SHALL NOT silently
  substitute a self-graded score.
  *(Cites: D-8, D-3.)*
- **REQ-G1.5** The eval SHALL reuse the existing prompt-eval isolation and
  hygiene disciplines (a disposable per-run worktree, budget caps, fail-closed
  teardown, allowlisted scalar-only recorded results), SHALL remain on-demand
  only, never wired into CI, and SHALL be registered under the `eval:` task
  namespace so `scripts/check-no-ci-evals.sh` covers it — the never-CI guard must
  see the new harness, not only `prompt-eval.sh`. The harness's `tmux` window
  SHALL carry a per-run-unique name and SHALL reap stale windows from crashed
  prior runs, so concurrent or leftover eval sessions never collide.
  *(Cites: D-8; the prompt-eval harness (Sources).)*
- **REQ-G1.6** The harness SHALL honor `security-posture`'s framework-script
  disciplines at its trust boundaries: persona-driver text is sanitized before it
  reaches `tmux send-keys` (no injected control input); the disposable worktree
  path is containment-checked after canonicalization before teardown; the
  structured decision/transcript log is emitted and parsed in a non-code-bearing,
  escape-safe form; artifact values surfaced to the pane pass the echo-safety
  sanitizer; only synthetic/fixture content (never a real spec bundle's
  operational detail) is sent to a third-party grader; grader-backend credentials
  are read from the environment or a secret store, never committed and never
  written into recorded results; the harness drives `/spec-kickoff` with
  publishing disabled (no remote, or `commit_on_kickoff` /
  `mark_spec_pr_ready_on_kickoff` off) so no eval run ever pushes, opens a PR, or
  marks a PR ready; and any sign-off record the driver produces is marked
  eval-only and non-authoritative so it can never be mistaken for a human
  sign-off.
  *(Cites: D-8; security-posture (Sources).)*

## REQ-H — Measurable acceptance

- **REQ-H1.1** The spec SHALL classify each interaction quality as either an
  assertable invariant (pinned `[test]`) or an experiential quality (scored by
  rubric and pilot), and `test-spec.md` SHALL reflect that split rather than
  defaulting the whole surface to `[manual]`.
  *(Cites: D-11.)*
- **REQ-H1.2** The assertable invariants SHALL include at least: a
  self-contained option set, an explicit reject option with no pre-selected
  default, the absence of verdict tokens, preserved normative tokens, and
  completeness (no readiness declared while a required decision is undefined).
  *(Cites: D-11; REQ-C1.1, REQ-D1.1, REQ-E1.1.)*
- **REQ-H1.3** The experiential qualities SHALL be scored against named
  rubrics — the CDC Clear Communication Index and the IPDAS balance criteria —
  by the independent grader (a non-Anthropic backend) with the human as final
  rater. A skill MAY run a self-audit against the rubrics as a diagnostic
  pre-pass, but the self-audit produces no score of record: the independent
  grader and the human are the only acceptance scorers, so the eval never
  collapses into the agent grading its own session (REQ-G1.4).
  *(Cites: D-11, D-3; research: CDC Clear Communication Index, IPDAS (Sources).)*
- **REQ-H1.4** The persona-parameterized eval (REQ-G1.2) SHALL be the
  acceptance path for the adaptive-level requirement, asserting the skill
  pitched differently and appropriately to a novice versus an expert operator.
  *(Cites: D-11; REQ-B1.3, REQ-G1.2.)*

## Changelog

- 2026-07-17: Bundle drafted at Status Draft via `/spec-draft`. Spun as a new
  bundle (fold-detection ran against `spec-comprehension`; the triggers fire —
  different external interface, an interaction doctrine plus the kickoff
  dialogue versus a standalone render command; independently ownable; orthogonal
  decision space — so it spins new and cites `spec-comprehension` as a Source).
  Design decisions D-1 through D-11 recorded; the three interaction disciplines,
  the in-band-comprehension bet, the preserved independence firewall, the
  self-contained-confirmation rule, and the TTY/persona behavioral eval
  established. Prior-art research consulted and recorded in Sources.

- 2026-07-17: Kickoff (first activation). REQ-A1.3's verification rescoped to the
  attended surfaces instantiated so far (`/spec-kickoff` this pass), with the
  deferred execution-side surfaces citing the doctrine when their behavior is
  reworked, so a manifest citation never precedes the behavior it promises
  (kickoff §3 REQ-A, 2026-07-17). Scope clarification; no REQ meaning changed.
- 2026-07-17: Kickoff. D-12 minted (recommendation vs. present-without-steering
  grounding test) reconciling the retained "selectors with a recommendation"
  rule with D-6's balance rules; REQ-D1.4 extended to require the grounding test
  in its self-audit and to cite D-12; Task 1 citations updated
  (kickoff §4, 2026-07-17). Meaning-class addition (new D-ID).
- 2026-07-17: Kickoff. `test-spec.md` intro tightened to state that the `[test]`
  tag covers two subsets — CI-run structural checks and on-demand
  behavioral-eval assertions (never CI, enforced by `check-no-ci-evals.sh`) — so
  a `[test]` tag alone is not read as CI coverage (kickoff §5, 2026-07-17).
  Expression-only clarification; no verification path changed.
- 2026-07-17: Kickoff sign-off lens pass (Discovery-Rigor, full bundle); ~25
  findings dispositioned (recorded in `kickoff-brief.md` §8). Applied: D-12
  reconciliation completed (REQ-D1.4 balance rules carved so a grounded
  recommendation is the admitted exception, no-pre-selected-default made
  unconditional, D-6/D-7 reconciled, REQ-E1.2 aligned); REQ-A1.3 reworded to
  attach the citation per-surface-at-instantiation; REQ-B1.5 gains MAY and the
  convey-vs-must-convey clause; REQ-C1.3 threshold hardened to "at most five";
  REQ-F1.4 regains never-auto-merge; REQ-G1.5 requires the harness under the
  `eval:` guard; **REQ-G1.6 added** (harness security disciplines); REQ-H1.3
  self-audit made a non-scoring diagnostic pre-pass; assorted consistency fixes
  across `design.md`/`tasks.md`/`test-spec.md`. Sources gain `instruction-hygiene`
  and `security-posture`; IPDAS expanded. Meaning-class (new REQ-G1.6; several
  REQ-meaning refinements).
- 2026-07-17: Kickoff `/panel-review --nested` pass (gemini backend, independent
  non-Anthropic angle). Applied 6 refinements + 1 new REQ: REQ-G1.6 gains
  grader-credential hygiene and a publishing-disabled constraint (no eval run
  pushes / opens a PR / marks a PR ready); REQ-G1.5 gains per-run-unique tmux
  window naming + stale-window reaping; REQ-G1.4 gains grader-failure degradation
  to the human rater; test-spec B1.5 splits mechanical verbatim-presence from
  semantic non-distortion; test-spec D1.3 strengthened to topical relevance;
  **REQ-C1.5 added** (interview input-robustness). Calibration-estimate shape left
  to Task 4 by decision. Meaning-class (new REQ-C1.5; harness-safety refinements).
- 2026-07-17: Post-sign-off lint fix (pre-merge, expression-only). Added the
  eight `## REQ-<Group>` section headers to `test-spec.md` so entries nest
  h1→h2→h3 (MD001/heading-increment; the drafted bundle skipped them and first
  hit `lint:md` on PR #225). No verification content changed; re-anchored via the
  kickoff-brief §9 amendment-log entry.

## Sources

- **interaction-style doctrine** — `doctrine/interaction-style.md`: the existing
  interaction rules (progress indicator, progressive disclosure,
  selectors-with-a-recommendation, running summary, the clerical/judgment split)
  whose declared scope is only the two authoring skills. This spec widens that
  scope and layers the three disciplines onto it.
- **instruction-hygiene** — `doctrine/instruction-hygiene.md`: the doctrine
  manifest convention (the `Doctrine: <load-model> <doc>` lines a skill declares)
  that REQ-A1.3's per-surface citation requirement rests on.
- **security-posture** — `doctrine/security-posture.md`: the artifact
  data-hygiene rules and the framework-script security disciplines (untrusted
  input, subprocess construction, path handling, serialization, echo discipline)
  that REQ-G1.6 binds the harness to.
- **the pinned altitude claim** — the operator's drafting-session framing
  (2026-07-17): the spec skills "were made with another bot as an audience... it
  does not feel like a peer review with a colleague where knowledge transfer and
  back-and-forth is expected." A doctrine-gap altitude assertion; its resolution
  is recorded as D-1 and cited from the Goal.
- **spec-comprehension** — `specs/spec-comprehension/` (Status Done): the
  independence firewall (the aid presents and structures; the human judges;
  REQ-D1.1) that this spec preserves, and the normative-token-preservation rule
  (REQ-C1.7) reused by REQ-B1.5. It owns `/spec-walkthrough`.
- **the spec-walkthrough failure** — operator feedback (2026-07-17):
  `/spec-walkthrough` "didn't work at all"; it was not intended to be on-demand
  only, and even on-demand it was not useful. Diagnosed as out-of-band friction
  (a separate command producing a browser artifact the operator must remember to
  open). Frames REQ-B1.1 (comprehension is in-band) and seeds the deferred
  walkthrough revisit.
- **skill-rigor** — `specs/skill-rigor/` (Status Ready): the adjacent in-flight
  spec hardening `/spec-kickoff`'s sign-off on the *mechanical* verification axis
  (re-derived claims, head-SHA CI gate, delta lens pass). This spec touches the
  same file on the *interaction* axis; REQ-F1.4 reconciles rather than collides.
- **the prompt-eval harness** — `scripts/prompt-eval.sh` and
  `tests/prompt-evals/` (origin: `prompt-hygiene`): the dependency-free POSIX-sh
  runner that drives a skill headlessly and grades observable outcomes with `jq`,
  pass^k, on-demand only. REQ-G reuses its isolation and hygiene disciplines.
- **the headless skill-injection gap** — the behavioral-pilot injection-design
  observation (2026-07-14): headless CLI slash-command skill injection is
  unavailable, leaving the kept prompt-eval suite guarded-inoperative. Motivates
  the TTY-session approach of REQ-G1.1.
- **the kickoff sign-off mechanicalness** — drafting-session reconnaissance
  (2026-07-17): `/spec-kickoff` cites `interaction-style` but drops it at the
  sign-off flow, which is a seven-step machine ritual (lens pass, anchor,
  disposition demand) with no shared-understanding summary. Frames REQ-F1.2.
- **instruction-headroom** — `specs/instruction-headroom/` and
  `check:instructions`: the hard start-load instruction budgets every skill- and
  doctrine-prose change must fit. Constrains REQ-A1.4 and REQ-F1.5.
- **obs:d0753832** — the self-contained-selectors observation
  (`specs/_observations/.../2026-07-14-self-contained-selectors-...`): a
  confirmation must carry its own context because prose above the selector is
  hidden by the operator's terminal. Instantiated by REQ-E.
- **research: NN/G confirmation dialogs** — never use OK/Yes/No; each option
  restates its consequence; the dialog is self-contained; no pre-selected
  default for consequential actions.
  <https://www.nngroup.com/articles/confirmation-dialog/>
- **research: progressive disclosure (NN/G)** — essentials first, detail behind
  a deferred layer. <https://www.nngroup.com/videos/progressive-disclosure/>
- **research: IPDAS balanced-information standards** — IPDAS = International
  Patient Decision Aid Standards; the non-directive
  presentation rules (parallel equal-detail options, equal-weight benefits and
  harms, neutralized ordering, explicit do-nothing option, no default).
  <https://journals.sagepub.com/doi/full/10.1177/0272989X211021397>
- **research: CDC Clear Communication Index** — a 20-item scored rubric for
  plain, comprehensible communication; adopted as an acceptance instrument.
  <https://www.cdc.gov/ccindex/pdf/clear-communication-user-guide.pdf>
- **research: ALEKS / Knowledge-Space-Theory, Zone of Proximal Development** —
  assess, then teach only the frontier between what the learner holds and the
  new material; scaffold and fade. <https://www.aleks.com/about_aleks/knowledge_space_theory>
- **research: docassemble backward-chaining** — goal-directed elicitation that
  cannot terminate while a required variable is undefined; a changed answer
  reopens dependents. <https://docassemble.org/docs/logic.html>
- **research: GitHub Spec Kit /clarify** — bounded (≤5) sequential question
  elicitation with answers encoded back into the artifact.
  <https://github.com/github/spec-kit>
- **research: legal information-vs-advice (UPL) line** — the enforceable bright
  line between presenting information and giving an outcome-driven verdict.
  <https://www.gavel.io/resources/legal-information-unauthorized-practice-of-law-legal-apps>
- **research: Khanmigo Socratic-guardrail failure mode** — a "never give the
  answer" guardrail with no escape valve reads as evasive; withhold the verdict,
  never the information. <https://www.khanmigo.ai/>
- **drafting-session decision (2026-07-17)** — choices made live that minted no
  D-ID: the spec identifier `operator-dialogue`, the approval-surfaces-first
  scope centered on `/spec-kickoff`, and the deferral of `/spec-walkthrough` and
  the execution-side handoffs.
