# Operator dialogue — Test spec

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix reflects the measurable-acceptance split (REQ-H1.1): the
assertable interaction invariants are `[test]` (structural checks and the
on-demand behavioral eval harness), the doctrine and skill-prose contracts are
`[design-level]` (their statement in the doc or skill is the verification), and
the experiential qualities are `[manual]` scored against the named rubrics (CDC
Clear Communication Index, IPDAS balance) with the human as final rater. Where
a REQ has both an assertable core and an experiential edge, the entry carries
both tags. The behavioral evals are on-demand only and never run in CI.

### REQ-A1.1 — Doctrine governs every attended surface [design-level]

`doctrine/interaction-style.md` states a scope covering every attended human
surface (comprehension, approval, handoff, report), not only the two authoring
skills. The doc's scope statement is the verification.

### REQ-A1.2 — Three disciplines defined [design-level]

The doctrine names and operationally defines teach-to-the-frontier,
interview-to-completeness, and present-without-steering. Existence and coverage
of the three sections is the verification.

### REQ-A1.3 — Skills cite the doctrine in their manifest [test]

A check greps the attended skills' doctrine manifests for the
`interaction-style` citation and fails if an attended surface omits it.

### REQ-A1.4 — Doctrine prose fits the instruction budget [test]

`check:instructions` passes for every skill that front-loads
`interaction-style`; a change that breaches a start-load wall fails the check.

### REQ-B1.1 — Comprehension is in-band [design-level + manual]

`skills/spec-kickoff/SKILL.md` builds comprehension inside the live dialogue
with no dependency on a separately-invoked artifact (design-level); a manual
pilot confirms the operator reaches understanding without leaving the session.

### REQ-B1.2 — Comprehend-first [design-level + manual]

The kickoff flow documents a faithful-comprehension step before it interviews
(design-level); a manual pilot confirms the skill's restatement of the spec is
accurate before questions begin.

### REQ-B1.3 — Teach the frontier and fade [test + manual]

The persona pilots (REQ-G1.2) assert the kickoff explained a familiar concept
more tersely to the expert persona than to the novice, and faded scaffolding
across sections (test); a manual read confirms the pitch was appropriate, not
merely different.

### REQ-B1.4 — Lightweight calibration, no learner model [design-level]

The kickoff documents a running per-concept uptake estimate and explicitly
bounds it away from a heavyweight learner model. The design statement is the
verification.

### REQ-B1.5 — Normative tokens preserved verbatim [test]

An assertion over a kickoff run's rendered explanation confirms every MUST /
SHALL / SHALL NOT / threshold / enumerated state from the source appears
verbatim and unsoftened.

### REQ-C1.1 — Completeness: no readiness with an undefined required decision [test]

Against a fixture spec with a known-required-but-undefined decision, the skill
does not declare the section or sign-off ready; supplying the decision lets it
proceed.

### REQ-C1.2 — Changed answer reopens dependents [test]

A fixture that changes an upstream answer asserts the dependent decisions it
invalidates are reopened rather than left stale.

### REQ-C1.3 — Bounded, need-driven questions [test + manual]

An assertion bounds the questions asked per pass (on the order of five); a
manual read confirms questions fired only when actually needed.

### REQ-C1.4 — Clerical/judgment split [design-level + manual]

The kickoff has the skill derive candidates and formatting while the operator
supplies judgment (design-level); a manual pilot confirms the operator was not
asked to do the skill's clerical work.

### REQ-D1.1 — No verdict [test]

An assertion over a kickoff run confirms the absence of verdict/score tokens
(no "this spec is good/ready-quality", no numeric quality score) in the skill's
own output.

### REQ-D1.2 — Information-versus-advice line [design-level + manual]

The doctrine states the line and the kickoff honors it (design-level); a manual
pilot confirms the skill presented information about the spec without an
outcome-driven verdict.

### REQ-D1.3 — Escape valve answers information requests [test + manual]

A persona that asks a direct information question receives the information
(test: the answer is present, not a mute refusal); a manual read confirms it
did not tip into a verdict.

### REQ-D1.4 — Balance rules and self-audit [test + manual]

A structural check asserts a presented fork gives options parallel equal-detail
treatment with no pre-selected default (test); an IPDAS-rubric manual pass
scores the balance of the surrounding prose.

### REQ-D1.5 — Natural-frequency probabilities [test]

An assertion confirms any surfaced likelihood uses a fixed-denominator natural
frequency and never a lone percentage or one-sided frame.

### REQ-E1.1 — Self-contained option set [test]

Task 2's structural check asserts each confirmation option restates its action
and consequence and the choice is answerable from the options alone.

### REQ-E1.2 — Explicit reject, no default [test]

The structural check asserts an equal-prominence reject/defer option is present
and no default is pre-selected on a consequential confirmation.

### REQ-E1.3 — No generic labels; stem restates [test]

The structural check flags OK/Yes/No/bare-"Approve?" option labels and asserts
the question stem restates in full what is being decided.

### REQ-E1.4 — Deeper detail is supplementary [design-level + manual]

The doctrine and kickoff make deeper detail an optional in-band layer, never
load-bearing for the choice (design-level); a manual pilot confirms the
confirmation was answerable without it.

### REQ-F1.1 — Kickoff instantiates the disciplines [design-level + manual]

`skills/spec-kickoff/SKILL.md` instantiates the three disciplines at each
section walk and at sign-off (design-level); a manual pilot confirms the walk
read as guided dialogue, not a mechanical ritual.

### REQ-F1.2 — Shared-understanding sign-off summary [test + manual]

An assertion confirms the "here is what you are about to approve and what
changes downstream" summary is emitted before the sign-off decision, replacing
the bare verdict-demand (test); a manual read confirms it built understanding.

### REQ-F1.3 — Plain-language gate framing [manual]

A CDC-Clear-Communication-Index pass scores the framing of the mechanical gates
(lens pass, anchor, CI) for plain language; the operator confirms they read as
what-they-protect, not machine tokens.

### REQ-F1.4 — Invariants intact; skill-rigor reconciled [test + design-level]

The existing kickoff invariant checks (two-key launch, no-auto-chain, draft-PR,
sign-off record + anchor) still pass (test); a design-level review confirms the
change reconciles with, and does not revert, `skill-rigor`'s sign-off changes.

### REQ-F1.5 — Kickoff prose fits the instruction budget [test]

`check:instructions` passes on the `spec-kickoff` surface after the
instantiation.

### REQ-G1.1 — TTY-session behavioral eval [design-level + test]

The harness drives a fixture skill through a real interactive TTY session and
completes a run (test); its existence and the not-headless approach is the
design-level record.

### REQ-G1.2 — Persona-parameterized driver [test]

The harness runs the same skill under a novice and an expert persona and
records both sessions' graded artifacts.

### REQ-G1.3 — Grade artifacts, not the pane [design-level + test]

Grading reads the run's written artifacts (kickoff brief, `tasks.md` state,
sign-off record, structured log); a check asserts the grader consumes files and
uses the pane only for liveness.

### REQ-G1.4 — Independent grader [design-level + manual]

The grader is a non-Anthropic backend and/or the human final rater, distinct
from the driver (design-level); a manual review confirms the eval does not
grade its own session.

### REQ-G1.5 — Isolation, hygiene, on-demand [test]

`scripts/check-no-ci-evals.sh` passes (the harness is not in CI), and the
harness reuses the disposable-worktree, budget-cap, fail-closed-teardown, and
allowlisted-scalar-result disciplines.

### REQ-H1.1 — Acceptance split reflected [design-level]

This file classifies every REQ as assertable (`[test]`) or experiential
(`[manual]` rubric) rather than defaulting the surface to `[manual]`. The file
itself is the verification.

### REQ-H1.2 — Assertable invariant set [test]

The named invariants (self-contained option set, explicit reject with no
default, no verdict tokens, preserved normative tokens, completeness) each have
a passing `[test]` entry above.

### REQ-H1.3 — Rubric-scored experiential quality [manual + design-level]

The CDC Clear Communication Index and IPDAS balance rubrics are documented as
runnable acceptance instruments (design-level) and applied as a self-audit /
independent-grader pass with the human as final rater (manual).

### REQ-H1.4 — Persona eval is the adaptive-level acceptance path [test + manual]

The novice/expert persona eval (REQ-G1.2) is the acceptance path for REQ-B1.3:
it asserts a divergence in explanation depth (test) that a manual read confirms
is appropriate to each persona.
