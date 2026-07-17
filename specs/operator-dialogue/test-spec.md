# Operator dialogue — Test spec

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix reflects the measurable-acceptance split (REQ-H1.1): the
assertable interaction invariants are `[test]`, the doctrine and skill-prose
contracts are `[design-level]` (their statement in the doc or skill is the
verification), and the experiential qualities are `[manual]` scored against the
named rubrics (CDC Clear Communication Index, IPDAS balance) with the human as
final rater. Where a REQ has both an assertable core and an experiential edge,
the entry carries both tags.

**The `[test]` tag here covers two subsets, and the tag alone does not imply CI
coverage** — the entry body names which subset it belongs to:

- **CI-run structural checks** — greps and structural assertions that run in the
  repo's CI via `mise run check` (an entry whose body says "a check greps…").
  This is `[test]` in the `spec-format` sense.
- **On-demand behavioral-eval assertions** — assertions over a real kickoff run,
  driven through the TTY harness (an entry whose body says "an assertion over a
  kickoff run…"). These are **on-demand only and never run in CI**; the
  exclusion is enforced by `scripts/check-no-ci-evals.sh` (REQ-G1.5). A lane-2
  `[test]` is assertable but is not a CI gate, so no coverage reading may treat
  it as CI-enforced.

### REQ-A1.1 — Doctrine governs every attended surface [design-level]

`doctrine/interaction-style.md` states a scope covering every attended human
surface (comprehension, approval, handoff, report), not only the two authoring
skills. The doc's scope statement is the verification.

### REQ-A1.2 — Three disciplines defined [design-level]

The doctrine names and operationally defines teach-to-the-frontier,
interview-to-completeness, and present-without-steering. The verification is
existence of the three sections AND that each states inspectable, operational
rules rather than a named tone: a section that names a discipline but states it
as tone (no inspectable rule) fails.

### REQ-A1.3 — Skills cite the doctrine in their manifest [test]

A check greps the doctrine manifests of the attended surfaces this spec has
instantiated (`/spec-kickoff` this pass; `/spec-draft` already cites it) for the
`interaction-style` citation and fails if an instantiated attended surface omits
it. The deferred execution-side surfaces (`/orchestrate`, `/execute-task`,
`/resume`, `/drain`) add the citation when their behavior is reworked (see the
`tasks.md` Deferred entry); the check's surface list widens with each
instantiation pass rather than demanding a citation ahead of the behavior that
honors it.

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

An assertion over a kickoff run's rendered explanation confirms that every
normative token the explanation DOES convey (MUST / SHALL / SHALL NOT / MAY /
threshold / enumerated state) appears verbatim and unsoftened; tokens for
concepts the run legitimately skips as already-held (REQ-B1.3) are not required
to appear. The check is non-distortion of what is presented, not presence of
every source token. (On-demand behavioral lane.)

### REQ-C1.1 — Completeness: no readiness with an undefined required decision [test]

An assertion over a kickoff run against a fixture spec with a
known-required-but-undefined decision confirms the skill does not declare the
section or sign-off ready; supplying the decision lets it proceed. (On-demand
behavioral lane; fixture and assertion built by Task 6.)

### REQ-C1.2 — Changed answer reopens dependents [test]

An assertion over a kickoff run, via a fixture that changes an upstream answer,
confirms the dependent decisions it invalidates are reopened rather than left
stale. (On-demand behavioral lane; fixture and assertion built by Task 6.)

### REQ-C1.3 — Bounded, need-driven questions [test + manual]

An assertion over a kickoff run bounds the questions asked per pass to at most
five (a sixth question in one pass fails); a manual read confirms questions fired
only when actually needed. (On-demand behavioral lane.)

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

Assertable slice (test): a structural check asserts a presented fork carries an
explicit equal-weight reject option and **no pre-selected default** (the
unconditional rule), and that where a recommendation is marked, it is marked but
not pre-selected. Rubric slice (manual): the parallel equal-detail treatment and
neutralized ordering — rubric qualities, not decidable predicates — and whether a
marked recommendation is genuinely grounded vs. taste (the grounding test) are
scored by an IPDAS-rubric manual pass over the surrounding prose.

### REQ-D1.5 — Natural-frequency probabilities [design-level + test]

The doctrine rule (any surfaced likelihood is a fixed-denominator natural
frequency, never a lone percentage or one-sided frame) stated in the doctrine is
the primary verification (design-level). The `[test]` slice is conditional: on a
kickoff run that surfaces a likelihood, an assertion confirms the
natural-frequency form. If no likelihood is surfaced the assertion is not counted
as coverage (no vacuous pass); the design-level statement carries the
requirement, and no task is required to force a likelihood scenario.

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

An assertion over a kickoff run confirms the "here is what you are about to
approve and what changes downstream" summary is emitted before the sign-off
decision, replacing the bare verdict-demand (test; assertion built by Task 6); a
manual read confirms it built understanding. (On-demand behavioral lane.)

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

### REQ-G1.4 — Independent grader [design-level + test + manual]

The grader is a non-Anthropic backend and/or the human final rater, distinct
from the driver (design-level); a check asserts the grader backend id differs
from the driver backend id (test); a manual review confirms the eval does not
grade its own session and that the REQ-H1.3 self-audit produced no score of
record.

### REQ-G1.5 — Isolation, hygiene, on-demand [test]

`scripts/check-no-ci-evals.sh` passes (the harness is not in CI), the harness is
registered under the `eval:` namespace so the guard actually matches it (not only
`prompt-eval.sh`) — a check confirms the harness runner is covered by the guard —
and the harness reuses the disposable-worktree, budget-cap,
fail-closed-teardown, and allowlisted-scalar-result disciplines.

### REQ-G1.6 — Harness security disciplines [design-level + test]

The harness honors `security-posture`'s framework-script disciplines: where
mechanically assertable, a check confirms persona-driver text is sanitized before
`send-keys`, the worktree teardown path is containment-checked after
canonicalization, the structured log is emitted/parsed in an escape-safe
non-code-bearing form, surfaced artifact values pass the echo-safety sanitizer,
only fixture content reaches a third-party grader, and any driver-produced
sign-off record is marked eval-only/non-authoritative (test); the stated
disciplines themselves are the design-level record.

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
runnable acceptance instruments (design-level) and applied by the independent
(non-Anthropic) grader with the human as final rater (manual); the in-session
self-audit is a non-scoring diagnostic pre-pass, never an acceptance scorer,
preserving REQ-G1.4 independence.

### REQ-H1.4 — Persona eval is the adaptive-level acceptance path [test + manual]

The novice/expert persona eval (REQ-G1.2) is the acceptance path for REQ-B1.3:
it asserts a divergence in explanation depth (test) that a manual read confirms
is appropriate to each persona.
