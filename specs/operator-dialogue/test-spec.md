# Operator dialogue — Test spec

**Status:** Ready
**Last reviewed:** 2026-08-25
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

*(Extension, 2026-08-24.)* The extension's entries mark their subset
explicitly — "(On-demand behavioral lane.)" for lane 2, "a unit test at the
script level" or "a check greps/runs" for lane 1 — and one lane-1 variant is
new: the **advisory** sidedness check (REQ-M1.3) runs in `mise run check`
reporting-only and never fails the build; its `[test]` claims cover the
check's own behavior (unit-tested detection, advisory wiring), never its
findings.

## REQ-A — The interaction doctrine

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
instantiated (`/spec-kickoff` and `/spec-draft` from the base pass; the four
execution-side surfaces once Tasks 9 and 11 land their instantiation) for the
`interaction-style` citation and fails if an instantiated attended surface
omits it. The check's surface list widens with each instantiation pass rather
than demanding a citation ahead of the behavior that honors it — the
extension's widening is Task 11's deliverable, and the REQ-K1.1 entry below
asserts the widened list. *(Amended at extension kickoff 2026-08-24: the
execution-side deferral this entry pointed at is consumed; the stale
Deferred-entry cross-reference removed.)*

### REQ-A1.4 — Doctrine prose fits the instruction budget [test]

`check:instructions` passes for every skill that front-loads
`interaction-style`; a change that breaches a start-load wall fails the check.

## REQ-B — Teach to the frontier

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
every source token. The verbatim-token-presence half is mechanical (the exact
token string appears where the concept is conveyed); the "unsoftened /
not-distorted" judgment is semantic and is scored by the independent grader or a
manual pass, not asserted mechanically. (On-demand behavioral lane.)

## REQ-C — Interview to completeness

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

### REQ-C1.5 — Input robustness [test + manual]

An assertion over a kickoff run feeding malformed/unparseable operator input
confirms the skill re-prompts rather than advancing the section or sign-off, and
that the running calibration estimate is unchanged by the garbage input (test;
fixture built by Task 6); a manual read confirms the re-prompt was intelligible.
(On-demand behavioral lane.)

## REQ-D — Present without steering

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
(test: the answer is present and topically relevant to the question asked — not
merely non-empty, and not a mute refusal); a manual read confirms it did not tip
into a verdict.

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

## REQ-E — Self-contained confirmation

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

## REQ-F — `/spec-kickoff` instantiation

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

## REQ-G — Behavioral eval harness

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
from the driver backend id (test); a check confirms that with the grader stubbed
unavailable the run degrades to human-rater scoring rather than failing and
substitutes no self-graded score (test); a manual review confirms the eval does
not grade its own session and that the REQ-H1.3 self-audit produced no score of
record.

### REQ-G1.5 — Isolation, hygiene, on-demand [test]

`scripts/check-no-ci-evals.sh` passes (the harness is not in CI), the harness is
registered under the `eval:` namespace so the guard actually matches it (not only
`prompt-eval.sh`) — a check confirms the harness runner is covered by the guard —
and the harness reuses the disposable-worktree, budget-cap,
fail-closed-teardown, and allowlisted-scalar-result disciplines. A check confirms
the harness's `tmux` window name is per-run-unique and that stale windows are
reaped, so two concurrent runs (or a leftover window from a crashed run) do not
collide.

### REQ-G1.6 — Harness security disciplines [design-level + test]

The harness honors `security-posture`'s framework-script disciplines: where
mechanically assertable, a check confirms persona-driver text is sanitized before
`send-keys`, the worktree teardown path is containment-checked after
canonicalization, the structured log is emitted/parsed in an escape-safe
non-code-bearing form, surfaced artifact values pass the echo-safety sanitizer,
only fixture content reaches a third-party grader, grader-backend credentials are
read from the environment/secret store and never appear in committed files or
recorded results, the harness runs the kickoff with publishing disabled so no
eval run pushes / opens a PR / marks a PR ready, and any driver-produced sign-off
record is marked eval-only/non-authoritative (test); the stated disciplines
themselves are the design-level record.

## REQ-H — Measurable acceptance

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

## REQ-I — The turn/artifact arbitration

Shared mechanics for the extension's behavioral-lane entries (REQ-I through
REQ-L): assertions grade the structured decision/transcript log's **turn
records** (D-19's additive schema growth; the grader stays artifact-only per
REQ-G1.3), and every fixture these entries name is Task 12's deliverable.

### REQ-I1.1 — Arbitration stated [design-level]

`doctrine/interaction-style.md` states the arbitration (completeness governs
artifacts, disclosure governs the turn, withholding-while-recording is not
pruning) and the colliding docs cite it at their emit mandates. The doctrine
statements are the verification.

### REQ-I1.2 — Bounded actionable projection [test + manual]

An assertion over an attended eval run confirms turn-side emissions carry a
projection (counts and actionable items, no full audit tables) and that the
full record exists in the governing artifact or is produced on a follow-up
request. (On-demand behavioral lane.) A manual read confirms the projection
was sufficient to act on.

### REQ-I1.3 — Actionability ordering [test]

An assertion over an attended eval run confirms decisions and questions
precede supporting state and bookkeeping in turn-side output. (On-demand
behavioral lane.)

### REQ-I1.4 — Sidedness declared [test]

The advisory sidedness check (REQ-M1.3) reports emit mandates lacking a
declared destination side; the touched docs and skills report clean at
landing. Advisory: the check informs, and this entry's `[test]` claim is the
check running and reporting, not a CI gate.

### REQ-I1.5 — Self-containment as floor, bounded density [test + manual]

An assertion over an attended eval run bounds selector identifier density
(numeric bound in the eval fixture, not doctrine) and confirms options carry
action and consequence; a manual read confirms plain language led and
identifiers appeared only where traceability needed them. (On-demand
behavioral lane.)

## REQ-J — Wall repairs

### REQ-J1.1 — Every turn-side mandate conforms; instance set repaired [test + design-level]

The turn-shape invariants run against the repaired surfaces at the acceptance
join (test; on-demand behavioral lane). A design-level review — the human at
Task 13's acceptance join, the same rater the rubric pass names — confirms
each sweep-recorded instance was repaired or carries a recorded disposition,
the dispositions recorded in the kickoff brief; none silently exempted.

### REQ-J1.2 — Loop-end handoff family projected [test]

An assertion over a review-loop eval run confirms no four-table dump in
turn-side output while the PR body (or, for `/polish`, the worktree-local
cache file `.claude/polish-audit.md`, D-16) carries the full record; a
`/polish` standalone fixture run produces that file. (On-demand behavioral
lane.)

### REQ-J1.3 — No monotonic summary [test]

An assertion over a multi-phase eval run confirms successive running
summaries do not grow monotonically (delta-plus-open form) and a resumed
kickoff confirms signed sections at one line each. (On-demand behavioral
lane.)

### REQ-J1.4 — Question-first read-only surfaces [test + manual]

An assertion over `/resume` and `/drain` fixture runs confirms the question
or actionable lanes lead and detail arrives only on request; a manual read
confirms the lead was sufficient to decide next steps. (On-demand behavioral
lane.)

### REQ-J1.5 — Unbounded payloads excerpted [test]

An assertion over an attended CI-failure fixture confirms the turn carries a
bounded excerpt plus an artifact pointer, never the full output. (On-demand
behavioral lane.)

## REQ-K — Execution-surface pass

### REQ-K1.1 — Four surfaces instantiate and cite [test]

A check greps the four execution-side skills' doctrine manifests for the
`interaction-style` citation (the REQ-A1.3 check's surface list widened to
include them) and fails if one omits it.

### REQ-K1.2 — Step report defined with slots [design-level + test]

`/orchestrate`'s prose defines the step report's state / reasoning / requests
slots (design-level); an assertion over an orchestrate eval run confirms the
emitted report carries the slot structure and that decision-shaped content
appears as captured items, not prose. (On-demand behavioral lane.)

### REQ-K1.3 — Orchestrate instances conform [test]

A unit test at the script level (Task 11's deliverable) asserts the
watch-loop attention render skips the full re-render when no derived-state
transition occurred — a bounded delta or a no-op both pass, an unchanged
full re-render fails; an assertion
over an orchestrate eval fixture with multiple simultaneous halts confirms
the batch is bounded and actionability-ordered. (Unit slice CI-run; behavioral
slice on-demand.)

## REQ-L — Capture at birth

### REQ-L1.1 — Capture at birth [test]

An assertion over an attended eval run with a planted action item (the
persona names a follow-up mid-dialogue and confirms the proposed form)
confirms the item exists in tracked state — an Awaiting-input or gated
Deferred entry, or an observation fragment, mirrored into the run's graded
artifacts — by run end, not only in transcript prose. (On-demand
behavioral lane.)

### REQ-L1.2 — Tracked-state targets [design-level]

The doctrine names the tracked-state target set and the ledger interface with
its degradation path. The statement is the verification; the companion
bundle's test-spec owns the ledger's own behavior.

### REQ-L1.3 — Skill proposes the tracked form [test + manual]

The planted-action-item assertion additionally confirms the skill proposed
the tracked form (the transcript shows a proposal turn preceding the
operator's confirmation); a manual read confirms the operator was not made to
transcribe. (On-demand behavioral lane.)

### REQ-L1.4 — Ship-gate for out-of-band fixes [design-level + manual]

The ship-gate rule is a kickoff lens-pass checklist item (design-level); the
human verifies at sign-off that any out-of-band fix named in the walked
bundle carries a task, gated deferral, or Awaiting-input entry (manual, same
class as the existing pairing checks).

### REQ-L1.5 — Session-visible open-captures list [test + manual]

An assertion over a multi-phase eval run confirms the open-captures list
appears at phase boundaries in delta-plus-open form; a manual read confirms
it answered "what is still owed" without prompting. (On-demand behavioral
lane.)

## REQ-M — Output-side enforcement

### REQ-M1.1 — Turn-shape invariants exist and run [test]

The harness runs the named invariants (no multi-table dump, projection
present, decisions-first, no monotonic growth, bounded density, capture)
against fixtures where a known wall fails and a known projection passes.
(On-demand behavioral lane.)

### REQ-M1.2 — Conformance pinned through the eval, not design-level [design-level]

This file's REQ-I/J/K/L entries carry `[test]` verification through the eval
for the behavioral half, with design-level reserved for entries whose
verification is a statement's existence (doctrine rules, defined structures)
or a named human review, and manual for experiential residue; the file itself
is the verification that the split holds.

### REQ-M1.3 — Advisory sidedness check [test]

The check runs over skill and doctrine prose, reports mandates lacking a
declared side, and exits zero; its unit test (Task 12) plants a deliberately
side-less mandate in a fixture under `tests/` — outside the scanned corpus,
so the live run stays clean — and asserts the check reports it, and the
advisory wiring is confirmed by `mise run check` remaining green while the
check reports. (CI-run structural lane for the check's own behavior; its
findings never gate.)

### REQ-M1.4 — On-demand only, never CI [test]

`scripts/check-no-ci-evals.sh` passes with the turn-shape extensions in
place; the extended invariants are registered under the `eval:` namespace the
guard covers.
