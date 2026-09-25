# Finding Categorization & the Act-Then-Review Gate

After [Discovery Rigor](discovery-rigor.md) produces findings and
[Validation Rigor](validation-rigor.md) confirms them, skills that act on
findings locally (such as `/self-review`, `/polish`, and the
convergence phase inside `/execute-task`) categorize each finding into one of
four buckets. The buckets are an **audit taxonomy, not a decision queue**
(REQ-C1.5): they record what kind of action the agent took and what evidence
backs it, so the human can review the whole record at the draft PR.

Citations: REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6,
REQ-C1.7 · D-4, D-5, D-6 · operator-dialogue REQ-I1.1, REQ-I1.2, REQ-I1.4 ·
operator-dialogue D-14, D-15 · prose-disposition REQ-B1.1, REQ-B1.5 ·
prose-disposition D-3 · human-gates REQ-B1.1.

The operational wiring is specified in [Gate Wiring](gate-wiring.md), which
implements the buckets and principles defined here.

## The principle: honest decision shape

The bucket is determined by what a human would honestly have to decide about
the finding. If the only call is "apply this known fix or not", the agent has
the call, with evidence recorded. If real alternatives exist that depend on
product priorities the agent cannot derive, the human does. The bucket a
finding lands in must match the kind of question it actually poses.

## The gate: act then review

The gate is exception-based and identical in every repository (REQ-C1.3).
Findings are applied on the branch with audit and evidence rows, and every
on-branch application is one revert from undone until the human's approval
act on the PR, which [Human Gates](human-gates.md) names; the draft→ready flip
approves nothing. There is no repository classification and no per-finding
permission prompt (D-5, D-6).

The intervention contract, in full, has two routes: a sign-off request (the
spec before execution; the draft PR and its pending-sign-off checklist after
it, which the human reviews and merges) and a hard pause mid-execution,
which reaches the operator as a tower's knock. Merge cadence is the autopilot's
throttle.

## The four buckets

A predicate condition that is uncertain routes the finding **downward** — to
Needs sign-off, or to Needs human judgment when the uncertainty is which path
to take rather than whether to apply a known fix — never upward.

### 1. Auto-applicable

The agent applies the fix immediately and records an audit row. All four
conditions must hold.

1. **Tool-grounded.** A named rule cited by a linter, formatter, type-checker,
   static analyzer, or dead-code detector the project ships, quoted in the
   audit row. "This looks like a bug" does not qualify.
2. **Mechanical fix.** A rename, reformat, drop-unused, missing import,
   missing newline, typo, inferable type annotation, or similar single-step
   transform. No design decision, no choice between alternatives.
3. **No user-observable behavior change.** Internal-only edits qualify.
   Anything that changes a public API, an error message a caller could depend
   on, log output a downstream consumer might parse, or any external contract
   does not.
4. **Validation passes converged with high confidence.** All three Validation
   Rigor passes agreed on the finding and the fix. Low-confidence or
   split-pass items are never Auto-applicable, however mechanical they look.

### 2. Agent-resolvable

The agent resolves the finding with the same discipline a careful engineer
would apply, and the audit row carries the proof. All four predicate
conditions must hold (REQ-C1.2).

1. **Failing-then-passing regression test.** A test exists that fails on the
   current code for the finding's exact reason, written and confirmed to fail
   *before* the fix, and passing unchanged after it.
2. **Passing project CI.** The project's full test, lint, and type-check
   suite passes after the fix, with no new regressions anywhere.
3. **Kickoff-brief alignment.** No contract drift relative to the active
   kickoff brief's goals, constraints, or decisions. If no kickoff brief is
   active for the current branch, the finding cannot be Agent-resolvable.
4. **Outside the hard-disqualifier zones.** Findings in the zones listed
   under Hard pauses below always route to Needs sign-off or Needs human
   judgment, regardless of how clean the test evidence is.

### 3. Needs sign-off

The agent has a single specific recommended fix and validation converged with
high confidence, but the change warrants explicit human review. Under
act-then-review the fix is **applied on the branch** and listed in a
**pending-sign-off checklist** in the draft PR description (REQ-C1.3): the
human approves it by the approval act [Human Gates](human-gates.md) names,
rejecting it before that act by its checklist recipe. No mid-loop prompt
fires for findings outside the hard-disqualifier zones, which pause first.

Route here when any of these hold:

- The fix touches a public API, error contract, log format, or any external
  interface.
- The fix causes a user-observable behavior change but the resolution is
  clearly correct.
- The change is in a hard-disqualifier zone and the agent has an unambiguous
  recommended fix (the zone still forces the hard pause first; see below).
- The fix is multi-step or non-mechanical but the path is unambiguous: one
  best fix, not a choice among alternatives.

### 4. Needs human judgment

Genuinely requires human input: the question is "which approach", not "yes or
no". Before a finding may route here it must climb the **resolution ladder**
(REQ-C1.7):

1. **Brief or spec citation.** Can the fork be answered from the kickoff
   brief or the spec bundle? If yes, proceed, citing the source.
2. **Research.** Can it be answered by [Research Rigor](research-rigor.md)
   (official docs, the library's own source and tests, issues and RFCs)? If
   yes, proceed, citing the findings.
3. **Project convention.** Can it be answered from the project's established
   patterns and sibling implementations? If yes, proceed, citing the
   precedent.

Only forks irreducible after all three rungs (genuine product or priority
calls, missing domain context the agent cannot derive, validation passes that
did not converge, contract changes requiring a policy call) queue for the
human, surfaced **at loop end** with bespoke options.

**Bespoke options, never timing labels.** The options presented must be the
actual decision branches: the concrete design alternatives, or a specific
question with concrete answers ("strict reject / lenient coerce"). Generic
timing options ("address now / defer / dismiss") are forbidden here. The
forcing function: if the options collapse to timing, the finding is
misrouted. A single recommended fix belongs in Needs sign-off, applied on the
branch with the checklist entry carrying the recommendation.

## Prose findings

A finding whose fix edits only prose — comments, documentation, doctrine,
skill instructions, spec bundles, configuration commentary — is classed on
[`spec-format.md`](spec-format.md)'s amendment axis, extended to prose:
**expression-only** when no normative statement changes meaning,
**meaning-class** otherwise. A new REQ or D-ID stays meaning-class; an added
sentence that states no normative statement is expression-only.

A **normative statement** is any obligation, permission, or prohibition
however worded, plus any threshold, enumerated value, or interface fact; it
changes meaning when it is added, removed, or altered. Enumerate an edited
passage's statements — the list a preservation check compares before and
after — with this search aid: MUST, SHALL, SHALL NOT, MAY, never, always,
only, must not. It is never the definition; a rule stated in none of those
words is still a normative statement. The list grows on
evidence by the ordinary doctrine-edit route: a changelog line,
expression-only unless a rule changes.

**Meaning-class prose on a surface that predates the PR keeps the
Needs-sign-off route**, and on a signed spec bundle is refused to a
`/spec-kickoff` delta re-walkthrough per the meta-spec's writer obligations.

## Declined-with-rationale (REQ-C1.6)

A first-class disposition, available for any validated finding: the agent may
close a finding without applying it, recording the reasoning in the audit
table. Declined findings remain visible at PR review and are re-raisable
there. Declining is not silent pruning; the rationale row is what
distinguishes a considered "no" from a dropped finding.

## Hard pauses (REQ-C1.4)

Exactly two things interrupt a loop mid-flight; nothing else does.

1. **Hard-disqualifier zones.** Findings or tasks touching
   security-sensitive code (authentication, authorization, secrets, crypto,
   permission boundaries, SQL or shell construction, sandbox boundaries),
   migrations or destructive operations (schema changes, backfills, deletes,
   anything irreversible), CI configuration, lockfiles, or secrets files.
2. **Irreducible Needs-human-judgment forks** that block further progress on
   the unit (forks that do not block continue to loop end and queue there).

A pause hands the disposition to the human: a zone finding's recommended fix
is not applied until the human directs it, however clear the fix looks.
Everything else flows through the gate to one of the five terminal
dispositions [Gate Wiring](gate-wiring.md) enumerates, without interrupting.

## Presentation (REQ-C1.5)

Skills using the categorization record the four buckets as **four tables in
fixed order**: Auto-applicable, Agent-resolvable, Needs sign-off, Needs human
judgment. An empty bucket still emits its table with a single `none` row (the
same anti-silent-pruning guard as Discovery Rigor's lens-coverage table). The
declined-with-rationale log accompanies the tables. The tables are
**artifact-side**: the audit record the draft PR carries to review; they are
not prompts.

A skill composing a turn *about* the pass emits a projection of that record
rather than the tables: per-bucket counts, the actionable residue, and where
the full record landed. Leaving the tables out of that turn is not pruning,
because the artifact still carries every row
([Interaction Style](interaction-style.md), the arbitration).
