# Validation Rigor

Discovery Rigor makes the finding list complete; Validation Rigor makes each
entry on it true. It has two halves: validating that an identified issue is
real, and validating that a fix actually resolves it.

Citations: REQ-D1.2, REQ-D1.8, REQ-D1.9.

## Issue identification: three independent passes per finding

For any workflow that flags issues, run at least **three independent
validation passes per finding**. Each pass must use a different method or
perspective, not the same approach repeated; the goal is to expose the blind
spots any single approach misses. If the three passes do not converge on the
same conclusion, drop the finding or downgrade it: a downgraded finding
survives only as low-confidence and routes to Needs human judgment in the
categorization (see
[finding-categorization.md](finding-categorization.md)).

- **Pass 1: direct reproduction.** When the claim concerns runtime behavior,
  reproduce it. Prefer **surface-relative whole-system end-to-end
  reproduction**: exercise the change through the surface's own mechanism
  rather than unit pieces alone. For a CLI, run the real command and observe
  its output, exit code, and side effects; for a web UI, drive it with
  browser automation; for a desktop app, drive it with UI automation. This is
  additive to, not a replacement for, unit-level reproduction: a unit test can
  pass while the real surface a user touches still fails, and the whole-system
  path catches the integration and wiring defects unit pieces miss. Otherwise
  reproduce as directly as the surface allows: write a failing test, run the
  code, trace through with concrete inputs, or construct the exact failing
  scenario. Where no whole-system surface or automation mechanism exists, fall
  back to the closest reproduction possible and record why. Inability to
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
  trackers, RFCs, and community sources surfaced by web search, per Research
  Rigor's source hierarchy. Note what was consulted in the finding.

## Adversarial re-validation: refute the keep set, resurrect the decline set

The three passes leave a **keep set** (findings to report or act on) and a
**decline set** (findings dropped or downgraded as non-converging). After
they run, and before that list is reported or acted on, run one adversarial
bi-directional re-validation pass over both sets:

- **Refute the keep set.** Take each kept finding as a false positive and try
  to break the case: the caller, input, or context that makes it not fire;
  the test that already proves it safe; the reading of the code that dissolves
  it. A finding that survives the attempt is stronger for it; one that is
  refuted moves to the decline set.
- **Resurrect the decline set.** Take each declined or dropped finding as
  prematurely dismissed and try to rebuild the case: the edge input the
  decline overlooked, the path the orthogonal angle did not walk, the source
  the outside-in pass did not consult. A decline that survives the attempt is
  more safely dropped for it; one that is resurrected moves to the keep set.

The two error directions are independent (a false positive in the keep set, a
false negative in the decline set), and the three passes guard only the
first. Re-validating both directions is the symmetric guard: the keep set
defends against over-reporting, the decline set against silently losing a
real finding.

The pass is a **single sweep** over each set. The keep→decline and
decline→keep reclassifications it produces are final for that sweep: a finding
refuted out of the keep set is not re-resurrected within the same pass, and a
finding resurrected into the keep set is not re-refuted. The pass terminates
deterministically rather than being iterated to a fixpoint, so it cannot
oscillate.

Its depth scales with stake and reversibility (see
[proportionality.md](proportionality.md)); a skill that scopes the pass (for
example, refuting only the findings it will act on autonomously and
resurrecting only the most load-bearing declines) must declare the scoping.
The default for any skill that does not declare otherwise is the full
bi-directional pass over both sets, the same discipline the three-pass
requirement follows.

## Solution validation

For any fix, validate with independent angles: angles 1 and 2 are the
default minimum, angle 3 is added when relevant, and the altitude check (4)
applies to every fix:

1. **Targeted test.** Write a test that fails on the current code for the
   bug's exact reason. Confirm it fails for the right reason before applying
   the fix. Apply the fix. Confirm the same test, unchanged, now passes.
   Prefer confirming the fix the same way Pass 1 prefers to reproduce the
   bug: through the surface's own mechanism (a CLI command run for real, a
   web UI driven by browser automation, a desktop app driven by UI
   automation), additive to the unit test. Where no whole-system surface or
   automation mechanism exists, fall back to the closest confirmation
   available and record why.
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
