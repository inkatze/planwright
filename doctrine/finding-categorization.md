# Finding Categorization & the Act-Then-Review Gate

After [Discovery Rigor](discovery-rigor.md) produces findings and
[Validation Rigor](validation-rigor.md) confirms them, skills that act on
findings locally (such as `/self-review`, `/polish`, and the
convergence step inside `/execute-task`) categorize each finding into one of
four buckets. The buckets are an **audit taxonomy, not a decision queue**
(REQ-C1.5): they record what kind of action the agent took and what evidence
backs it, so the human can review the whole record at the draft PR.

Citations: REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6,
REQ-C1.7 · D-4, D-5, D-6.

The operational wiring (routing order, commit discipline, the checklist and
audit-record formats, the ladder procedure, the pause protocol) is specified
in [Gate Wiring](gate-wiring.md), which implements the buckets and
principles defined here.

## The principle: honest decision shape

The bucket is determined by what a human would honestly have to decide about
the finding. If the only call is "apply this known fix or not", the agent has
the call, with evidence recorded. If real alternatives exist that depend on
product priorities the agent cannot derive, the human does. The bucket a
finding lands in must match the kind of question it actually poses.

## The gate: act then review

The gate is exception-based and identical in every repository (REQ-C1.3).
Findings are applied on the branch with audit and evidence rows; nothing
reaches a reviewer before the author flips the draft PR to ready, and every
on-branch application is one revert from undone. The author's draft→ready flip
is the universal review gate. There is no repository classification and no
per-finding permission prompt (D-5, D-6).

The intervention contract, in full: the human signs off the spec before
execution; during execution only hard pauses interrupt (see below); after
execution the human reviews the draft PR (diff plus pending-sign-off
checklist) and merges. Merge cadence is the autopilot's throttle.

## The four buckets

### 1. Auto-applicable

The agent applies the fix immediately and records an audit row. All four
conditions must hold; if any is uncertain, the finding routes to Needs
sign-off (or Needs human judgment when the uncertainty is about which path to
take rather than whether to apply a known fix).

1. **Tool-grounded.** A specific rule was cited by a linter, formatter,
   type-checker, static analyzer, or dead-code detector run against the
   project. "This looks like a bug" does not qualify; a named rule from a tool
   the project ships does. The rule citation appears in the audit row.
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
conditions must hold (REQ-C1.2); if any is uncertain, the finding routes to
Needs sign-off (or Needs human judgment when the path itself is ambiguous).

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

The audit row records the test path, the before and after test output, the CI
run and result, and the brief-alignment citation.

### 3. Needs sign-off

The agent has a single specific recommended fix and validation converged with
high confidence, but the change warrants explicit human review. Under
act-then-review the fix is **applied on the branch** and listed in a
**pending-sign-off checklist** in the draft PR description (REQ-C1.3). The
human approves by leaving it in place and rejects with one revert, at PR
review. No mid-loop prompt fires for findings outside the hard-disqualifier
zones (which pause first; see Hard pauses).

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
question with concrete answers ("strict reject / lenient coerce", "retry the
full operation / retry the failed sub-step / fail fast"). Generic timing
options ("address now / defer / dismiss") are forbidden in this bucket. The
forcing function: if the options collapse to timing, the finding is
misrouted. A single recommended fix belongs in Needs sign-off, applied on the
branch with the checklist entry carrying the recommendation.

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

Everything else flows through the gate without interrupting: applied,
resolved with evidence, applied pending sign-off, declined with rationale, or
queued for loop end.

## Presentation (REQ-C1.5)

Skills using the categorization present the four buckets as **four tables in
fixed order**: Auto-applicable, Agent-resolvable, Needs sign-off, Needs human
judgment. An empty bucket still emits its table with a single `none` row (the
same anti-silent-pruning guard as Discovery Rigor's lens-coverage table). The
declined-with-rationale log accompanies the tables. The tables are the audit
record the draft PR carries to review; they are not prompts.
