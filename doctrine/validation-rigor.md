# Validation Rigor

Discovery Rigor makes the finding list complete; Validation Rigor makes each
entry on it true. It has two halves: validating that an identified issue is
real, and validating that a fix actually resolves it.

Citations: REQ-D1.2.

## Issue identification: three independent passes per finding

For any workflow that flags issues, run at least **three independent
validation passes per finding**. Each pass must use a different method or
perspective, not the same approach repeated; the goal is to expose the blind
spots any single approach misses. If the three passes do not converge on the
same conclusion, drop or downgrade the finding (non-convergence also routes a
surviving finding to Needs human judgment in the categorization; see
[finding-categorization.md](finding-categorization.md)).

- **Pass 1: direct reproduction.** When the claim concerns runtime behavior,
  reproduce it. Write a failing test, run the code, trace through with
  concrete inputs, or construct the exact failing scenario. Inability to
  reproduce is a strong signal the issue may not exist.
- **Pass 2: orthogonal angle.** Use a different lens than pass 1: callers
  and upstream context, related code paths and side effects, project
  conventions and sibling implementations, existing test coverage that may
  already prove the case safe.
- **Pass 3: outside-in angle.** Consult sources outside the diff. Git
  history and blame for why the code is the way it is. Repo-wide search for
  similar patterns. For text or research-based claims (API correctness, spec
  compliance, deprecated patterns, security claims, library behavior):
  official documentation, the library's own source and tests, issue
  trackers, RFCs, web search, per Research Rigor's source hierarchy. Note
  what was consulted in the finding.

## Solution validation

For any fix, validate with at least two independent angles, four when
relevant:

1. **Targeted test.** Write a test that fails on the current code for the
   bug's exact reason. Confirm it fails for the right reason before applying
   the fix. Apply the fix. Confirm the same test, unchanged, now passes.
2. **Wider check.** Run the full project test suite, linters, and
   type-checkers. Watch for regressions, including in unrelated areas the
   change could now affect.
3. **Edge / integration / manual.** When relevant: boundary cases (null,
   empty, max size, concurrency), integration or smoke tests, manual
   exercise of the user-facing flow.
4. **Altitude check.** Confirm the fix addresses the cause rather than a
   symptom, at the right layer. A fix that patches the call site of a broken
   function, special-cases one input to a general routine, or silences a
   signal instead of resolving its source passes tests and still fails this
   check. Ask where the defect actually lives and whether the change lands
   there.

## Non-testable changes

For documentation, comments, formatting, pure renames, and type-only
adjustments, substitute review angles for the test angles: re-read the diff,
read it from the perspective of each consumer, and search the repository for
places the change could silently break. For contract rewords (a rule
expressed in several places, a behavior summary that recurs across docs, a
rename touching prose as well as identifiers): search the affected files for
the surface patterns of the rule before declaring alignment, not only the
lines a finding points at; otherwise stragglers surface as new findings in
the next cycle. Record why no test was added.

## Scoping and proportionality

Rigor scales with stake and reversibility (see
[proportionality.md](proportionality.md)). A skill may scope the three-pass
requirement, for example applying the full three passes to findings it will
act on autonomously and a spot-check to findings a human will review anyway,
but the scoping must be declared in the skill. The default for any skill
that does not declare otherwise is the full three passes on every finding.
