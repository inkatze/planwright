# Seed brief: amend `model-allocation` (review steps default to Sonnet)

Captured 2026-11-09 by the performance and token-spend flight
(`docs/research/token-spend-2026-11.md`, cut 2). The operator chose "Sonnet +
amend both (Recommended)".

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend model-allocation

The bundle derives **Done**, so extending it triggers the reopen cycle; the
scoped kickoff of the delta flips it back.

## The change

- `config/defaults.yml`: `allocation_model_step_polish` and
  `allocation_model_step_self_review` ship `sonnet` (were `inherit`). Their
  effort knobs stay `inherit`. Implementation and every non-review step stay
  `inherit`.
- `docs/allocation.md`: the shipped-posture list and the example block match.
- `tests/test-review-step-sonnet-default.sh` pins the shipped values.

## What it does and does not do yet

It changes the shipped value, not the runtime. The resolver refuses a step
tier at a surface whose own tier is `inherit`, and `allocation_model_execute_step`
(the per-step session surface) ships `inherit`. So the review step model
applies only once that surface carries a tier. Giving it one is a separate
operator decision and is the next sign-off item here.

## Decision for the operator

Overturns D-13's "shipped defaults change nothing" for the two review steps,
on the operator's explicit call. Review quality on Sonnet is not measured
here; the saving is a cost estimate.

## Measured saving (from the research note, not re-measured)

- Review and verification sub-agents, mission-control era (2026-11-05 to
  2026-11-08): 501 agents, $795, of which cache writes $362 and output $219.
  Halving writes and output (Sonnet's rates against Opus 5.5's) saves about
  $290 in the era (derived: $181 + $110).
- Full history: the note's figure is about $800 for the same change.
- Reads cost the same on both models, so tokens are unchanged.

## Why not "inherit" with a note

The shipped default is the operator's stated choice; leaving it at `inherit`
would leave the cut unshipped on every adopter's machine.
