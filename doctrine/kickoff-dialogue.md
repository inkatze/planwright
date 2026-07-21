# Kickoff dialogue — instantiating the interaction disciplines

How `/spec-kickoff` instantiates `interaction-style`'s three disciplines in-band
across its guided walkthrough and sign-off, plus the two artifacts that
instantiation adds: the shared-understanding approval summary that replaces the
bare verdict-demand, and the structured decision/transcript log the behavioral
eval grades. `interaction-style` defines the disciplines and session mechanics;
this doc records how the kickoff surface applies them. The skill names each at
its point of use and follows the mechanics here; lifting them out keeps
`skills/spec-kickoff/SKILL.md` within its instruction budget (D-10) while the
full instantiation stays authoritative in one place.

Citations: operator-dialogue REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5,
REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-F1.1,
REQ-F1.2, REQ-F1.3, REQ-G1.3, REQ-G1.6, REQ-H1.3 · operator-dialogue D-2, D-3,
D-4, D-5, D-6, D-9, D-10.

## Comprehend before interviewing (teach to the frontier, D-2)

Kickoff builds its faithful model of the spec **in-band, before it interviews**
— inside the live dialogue where the operator already is, with no separate
command or generated file on the critical path (the optional
`/spec-walkthrough` cold read stays a suggestion, never a dependency; the
walkthrough's out-of-band failure is the direct evidence, D-2). The Goal &
glossary restatement (walkthrough section 2) is that comprehension step: the
agent restates what the spec is for, rules out, and assumes, and surfaces
implicit terms, before the requirements interview begins.

Teaching happens inside the same dialogue, pitched at the operator's frontier —
skip what the operator demonstrably already holds, teach the gap, and let
scaffolding fade across sections so a later section is not re-explained at the
depth of the first. **Normative tokens are preserved verbatim.** Any normative
token the explanation does convey — MUST, SHALL, SHALL NOT, MAY, a threshold, an
enumerated state — appears unsoftened, never paraphrased into vague prose
(REQ-B1.5). Tokens for concepts the run legitimately skips as already-held are
simply not conveyed; non-distortion of what *is* presented is the rule, not
presence of every source token.

## Adaptive-level calibration: the running per-concept estimate (D-4)

The depth each explanation is pitched at (the frontier teaching above) is driven
by a **lightweight running per-concept estimate** of what the operator has picked
up — a run-local heuristic sense, held per concept (a spec term, a requirement's
intent, a design rationale, a pipeline mechanic) and updated as the dialogue
proceeds. It is not a stored profile, a score, or a formal learner model.

- **Frontier detection (REQ-B1.3).** Before explaining a concept, the skill reads
  what the operator has already demonstrated about it — a correct restatement in
  their own words, a question that presupposes it, an answer that applies it, or
  explicit prior exposure. A concept demonstrably held is skipped or named in
  passing; the gap between what the operator holds and what the section needs is
  what gets taught. Demonstrated command raises the estimate for that concept; a
  confusion signal (a mis-restatement, a question exposing a gap) lowers it and
  pulls the explanation back down.
- **Fade across sections (REQ-B1.3).** As the estimate rises the scaffolding
  tapers: a concept taught in full early is referenced, not re-derived, when it
  recurs later, and the shared vocabulary the early sections built is assumed.
  Fade is **per concept, not global** — an operator fluent in the requirements
  vocabulary but new to the task-graph mechanics still gets the task graph taught.
- **The no-model bound (REQ-B1.4, D-4 proportionality).** The estimate stays
  deliberately lightweight: a running sense carried in the live dialogue, never
  knowledge tracing, a knowledge-space lattice, an HMM, or any machinery that
  models the operator formally — the borrowable core is "teach the frontier,
  fade," not the learner model behind it. When uptake is uncertain the skill
  teaches rather than guesses held: an over-explanation costs a sentence, a wrong
  skip loses the operator.
- **The estimate never absorbs garbage (REQ-C1.5, REQ-B1.4).** Input the skill
  cannot parse leaves the per-concept estimate exactly where it was (it earns a
  re-prompt, per *Interview to completeness*), so malformed input can neither
  inflate a concept to "held" nor corrupt the calibration that drives later depth.

Depth is all this varies: a normative token that a presented concept carries
stays verbatim, however tersely it is pitched (*Comprehend before interviewing*,
REQ-B1.5) — skipping a held concept is allowed, softening a presented one is not.

## Interview to completeness by backward-chaining (D-5)

At kickoff the "dependency structure" the interview chains over is the
**bundle's own open questions and cross-references** — the bundle is already
authored, so a "required decision left undefined" is an open question or an
unresolved inconsistency, and "reopen dependents" reopens the brief decisions an
amended answer invalidates.

- **No premature readiness (REQ-C1.1).** No section and no sign-off is declared
  ready while a decision the spec's structure requires is still undefined; this
  is the discipline behind the inconsistency-halt and the
  no-sign-off-with-open-questions rule.
- **Changed answer reopens dependents (REQ-C1.2).** An amended upstream answer
  reopens the dependent brief decisions it invalidates rather than leaving a
  stale answer standing.
- **Bounded, need-driven (interaction-style).** At most five questions per
  multi-turn pass, asked only when actually needed, so the interview converges
  rather than interrogates.
- **Clerical/judgment split (REQ-C1.4).** The skill carries the clerical weight
  — deriving candidate answers, formatting, tracking state — and asks the
  operator only for judgment, never for the skill's own bookkeeping.
- **Input robustness (REQ-C1.5).** Operator input the skill cannot parse gets a
  re-prompt restating what is needed, never a silent advance; garbage input does
  not move the section, the sign-off, or the running uptake estimate.

## Present without steering (D-3, D-6)

The walk and sign-off present information *about* the spec — what a decision
says, what it depends on, the tradeoffs the design already records — and
**never** deliver a verdict, score, pass/fail, or quality assessment of the spec
on the skill's own behalf (the independence firewall, D-3; REQ-D1.1, REQ-D1.2).
The escape valve holds: withhold the quality verdict, never information the
operator asked for — a mute refusal of a direct information request is a defect,
not compliance (REQ-D1.3). Every fork the walk presents applies
`interaction-style`'s balance rules with the self-audit, and any recommendation
is marked only when it passes the grounding test.

## The shared-understanding approval summary (D-2, D-9; REQ-F1.2)

Immediately before the sign-off decision, kickoff emits a compact **"here is
what you are about to approve, and what changes downstream"** summary — this
replaces a bare verdict-demand ("does this look good?"), which asks the operator
to certify quality the skill will not itself assess. The summary restates, as
information the operator can act on:

- **What is being approved:** the decisions the brief now records (goal, the
  reconciled requirement and design ledgers, the risk register), in the
  operator's own terms.
- **What changes downstream:** that sign-off arms the first key of the two-key
  launch — the Draft→Ready flip, the spec PR readied for merge — and that the
  merge (the human's second key) is what makes the Ready spec operational; the
  first dispatch then derives Active. It changes nothing the operator has not
  seen.

The summary builds shared understanding of the consequence; it is not a verdict.
The confirmation that follows is **self-contained** per `interaction-style`'s
*Confirmations* rule: each option restates its own action and consequence, an
explicit reject/defer option sits at equal prominence, and no option is
pre-selected as a default. The choice is answerable from the option set alone;
deeper detail is an optional in-band layer, never load-bearing.

## Plain-language gate framing (REQ-F1.3)

The mechanical gates the sign-off runs are framed to the operator as **what they
protect**, not machine tokens. The skill still runs each gate by its recorded
mechanics (`kickoff-verification`); this governs only the operator-facing
rendering, which stays terse and jargon-free:

- **The lens pass** — a last review of the spec itself for the kind of bug
  execution feedback cannot catch, before the spec is committed to.
- **The anchor** — a fingerprint of the exact spec bytes being signed off, so
  execution later refuses to run against a spec that drifted since sign-off.
- **The CI gate** — a check that the spec PR's own tests are green on the exact
  commit before the PR is offered for merge.

## The structured decision/transcript log (REQ-G1.3, D-9)

Kickoff emits a structured decision/transcript log as a durable artifact the
behavioral eval **reads and grades** — the harness grades written artifacts, never
a scraped pane (REQ-G1.3). It is a run-local diagnostic, not part of the signed
bundle: the committed artifacts stay the brief and the four spec files.

- **Form.** JSON Lines — one self-contained JSON object per line, appended as the
  session proceeds. This is escape-safe and non-code-bearing by construction:
  the log is emitted and parsed as **data, never executed**, and every surfaced
  value is treated as data per `security-posture`. Each record carries a schema
  version (`v`), a monotonic `seq`, the `phase`, a `kind`
  (`present` / `ask` / `answer` / `decision`), and its payload; the schema is
  versioned so the grader contract survives a format change.
- **Records.** Each presentation, question, operator answer, and recorded
  decision across the walk and sign-off — including the approval summary and the
  final sign-off decision — is one record. Operator answers are captured
  verbatim after the echo-safety sanitizer, so no surfaced value carries a
  control sequence into the log.
- **Independence.** The log records what was presented and decided; it carries
  **no** self-graded verdict or score of the spec. The in-session self-audit is a
  non-scoring diagnostic, never an acceptance score of record (REQ-H1.3,
  preserving the independence firewall).
- **Eval-only runs.** Under the behavioral-eval harness the kickoff runs with
  publishing disabled — no push, no PR, no ready-flip — and any driver-produced
  sign-off record is marked eval-only / non-authoritative, so an eval run never
  mutates a real bundle's pipeline state (REQ-G1.6). The schema and the emit path
  are pinned with the harness; grader-backend credentials never appear in the
  log.

## Degradation

Absent this doc, `/spec-kickoff` follows the load-bearing spine inline: comprehend
the spec in-band before interviewing, pitch each explanation at the operator's
frontier and fade scaffolding across sections via a lightweight per-concept uptake
estimate (no learner model), interview to completeness by
backward-chaining the bundle's open questions (bounded per pass), present without
steering, emit the shared-understanding approval summary in place of a
verdict-demand, frame the gates in plain language, and emit the structured
decision/transcript log — and it notes the missing doc. `interaction-style`
(run-start) still supplies the discipline definitions the spine instantiates.
