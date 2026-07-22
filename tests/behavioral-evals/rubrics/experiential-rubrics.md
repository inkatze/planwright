# Experiential-quality rubrics — CDC CCI + IPDAS balance

The measurable-acceptance split (REQ-H1.1) divides every interaction quality into
two lanes:

- **Assertable invariants** — pinned `[test]`, graded mechanically (the kickoff
  fixture's `grade.jq`, `check-confirmation.sh`, `check-doctrine-manifest.sh`,
  and the assertions in `tests/test-behavioral-eval-kickoff.sh`).
- **Experiential qualities** — scored against *named rubrics* by an **independent
  grader** with the **human as final rater** (REQ-H1.3). This file is that
  instrument: what the rubrics are, who scores, and how to run them.

The two named rubrics are the **CDC Clear Communication Index (CCI)** and the
**IPDAS balance criteria**. They are documented here as *runnable acceptance
instruments*; the runnable pieces are `scripts/rubric-grade.sh` (the grader) and
`scripts/rubric-self-audit.sh` (the non-scoring diagnostic).

## The independence firewall (REQ-G1.4, REQ-H1.3)

Experiential scoring must never collapse into the agent grading its own session.
So the roles are split, and only two of them produce a score of record:

| Role | Who | Produces a score of record? |
| --- | --- | --- |
| Diagnostic self-audit | the skill, on its own run (`rubric-self-audit.sh`) | **No** — observations only |
| Independent grader | a non-Anthropic backend (`rubric-grade.sh` under a distinct id) | Yes — a mechanical floor |
| Final rater | the human | Yes — the authority |

The self-audit is a *pre-pass*: a skill may run it to catch a shortfall before
handoff, but its output carries no verdict and no number. The independent grader
applies the same criteria and emits `pass`/`fail`; the harness refuses to run a
grader whose id equals the driver's (self-grading). The human is always the final
rater — a grader `pass` is the floor the human confirms, not a substitute for
the human's read of whether the prose genuinely communicates.

## The criteria

Both runnable tools apply the same mechanical **proxies**. A proxy checks a
*structural signal* of clear, balanced communication over the run's durable
artifacts (the decision log and sign-off) — it cannot judge whether prose reads
well, which is exactly what the human final rater is for.

### CDC Clear Communication Index (CCI)

- **Shared-understanding summary present.** The run emits a "here is what you are
  about to approve, and what changes downstream" summary before the sign-off
  decision (REQ-F1.2).
- **Actionable — names the downstream effect.** The summary states what changes
  downstream when the operator approves, so the decision is made in context.
- **Natural frequencies, no lone percentage.** Any surfaced likelihood is a
  fixed-denominator natural frequency (e.g. 8 in 10), never a lone percentage or
  a one-sided frame (REQ-D1.5).

### IPDAS balance

- **Explicit equal-weight reject.** Any presented confirmation carries an
  explicit reject/defer option at equal prominence (REQ-E1.2).
- **No pre-selected default.** No confirmation option is pre-selected as the
  default — unconditional (REQ-D1.4, REQ-E1.2).
- **No self-verdict on the spec.** The run delivers no quality verdict, score, or
  pass/fail on the spec on its own behalf; it presents information, the human
  decides (REQ-D1.1).

The proxies are a *floor*, not the whole rubric: parallel equal-detail
presentation, neutralized ordering, and whether a marked recommendation is
genuinely grounded versus taste (the grounding test, D-12) are qualities the
human rater scores by reading the surrounding prose. The mechanical floor keeps
the obvious failures from ever reaching the human; the human catches the rest.

## Running the instruments

The merged fixture-only artifacts object (the shape the behavioral-eval harness
passes a grader) is the input to both tools:

```sh
# The independent grader — prints `pass` or `fail`, exit 0; wire it into the
# harness as the --grader (with an id distinct from the driver):
scripts/behavioral-eval.sh \
  --grader scripts/rubric-grade.sh --grader-id ext-rubric-panel \
  tests/behavioral-evals/fixtures/kickoff

# The non-scoring diagnostic self-audit — per-criterion observations, no verdict:
scripts/rubric-self-audit.sh <merged-artifacts.json>
```

The self-audit exits 0 and emits `diagnostic: <criterion>: met | not met` lines
under a `NOT A SCORE OF RECORD` banner — never `pass`/`fail`/a number, so it can
never be mistaken for an acceptance score.

On demand only: the behavioral eval and its graders are never wired into CI
(`scripts/check-no-ci-evals.sh` enforces this, REQ-G1.5). The hermetic tests
`tests/test-rubric-instrument.sh` and `tests/test-behavioral-eval-kickoff.sh`
exercise the instruments and fixtures deterministically under a stub tmux, and
those tests do run in CI.
