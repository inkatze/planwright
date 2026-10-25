# Seed brief for `night-shift` (a follow-on bundle of `mission-control`)

Suggested invocation (fresh Claude session in the planwright repo, this file is the seed):

    /spec-draft night-shift

Read this whole brief before eliciting. Run fold-detection against `quota-handling` (owner of the
`limited` outcome and quota holds), `tower-comms` (owner of away mode and the push channel) and
`fleet-autonomy` before assuming a new bundle; this brief does not prejudge extend-vs-spin-new.

## Why this is a follow-on, not part of `mission-control`

The operator's drafting-session asides named a budgeted night shift; `mission-control` keeps
working while the operator is away (its Goal) but scoped the deliberate, budgeted use of that time
out as a follow-on, so the core's budget and degradation ladder stay the only limits it decides
(D-17, D-22, D-27).

## The shape (from the mission-control drafting asides and kickoff)

A **duty** that plans and runs a bounded block of unattended work when the operator signs off for
the night (or any long absence): choose the units whose next steps need no human gate, schedule
heavy work against the off-hours host and quota budget, stop at every gate rather than queue past
it, and hand the operator a prepared morning packet of what moved, what parked and why, ordered by
what needs them first. It never merges, flips outside the configured policy, or sends to a person
(mission-control REQ-I1.1 to REQ-I1.3); a parked unit never holds the rest.

## Seams it consumes from `mission-control`

- **The duty catalog** (D-3, REQ-C1.1 to REQ-C1.6), starting in `shadow` (D-15).
- **The budget and its degradation ladder** (D-17, REQ-L1.2): the shift is a budget window with
  its own spend class and rungs, reusing quota-handling's `limited` outcome.
- **The launcher** (D-10): every session the shift starts goes through it.
- **Liveness and the stall detector** (D-11): an overnight stall is an event, never discovered in
  the morning.
- **The queue and prepared packets** (D-7, D-25, REQ-F1.4, REQ-F1.14): items wait for the operator's
  return; the morning packet is a prepared moment.
- **Handover** (D-29, D-30): a shift longer than one session's context hands over losslessly.

## Observations left live for this bundle

- obs:09e7b4f0: at the fleet tier, the one most likely to run unattended, selector warnings are
  suppressed and a fully held fleet shares an exit code with nothing-ready, so an unattended loop
  cannot tell retry from stop.
- obs:53a1587a: a tower running for days lost its dispatch prompts to temp cleanup and a review
  pass was silently skipped (also routed to `environment-broker`).
- obs:50ed8b31: the away push pass costs one event-log re-exec per item, so its cost grows with
  the backlog waiting for the operator's return (`tower-comms` owns away mode; still live).

The evidence is thin in the observations log; the stronger record is the mission-control hub's
overnight runs (its Sources), neutralized.

## Open questions for the drafter

1. What starts and ends a shift: an operator act, a schedule, presence, or all three.
2. How units are chosen for a shift and how the shift's budget is set against the day's.
3. The morning packet's shape, and how it composes with the first turn after silence
   (mission-control REQ-A1.7).
