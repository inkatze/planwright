# Seed brief: amend `mission-control` (hand over long-lived sessions at 200k context)

Captured 2026-11-09 by the performance and token-spend flight
(`docs/research/token-spend-2026-11.md`, cut 1). Behaviour is unchanged by
this note; it is the proposal for sign-off.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend mission-control

## The change

- Lower the shipped `mission_control_handover_context` from 70 to 20 (a
  context percent: a 200k trigger on a 1M window). Reaches only a launched
  hub.
- Towers and `/orchestrate --watch` need a context trigger of their own.
  `context_budget_threshold` counts orchestration steps, not context
  (orchestration-fleet REQ-C1.1, D-4), so a lower step count does not do it.
  Their trigger is a separate knob.

## Decisions for the operator

- Covering attended hubs too means reopening D-42. An attended hub compacts
  instead of handing over (REQ-L1.5, which holds for a launched holder only
  per REQ-L1.8; D-29 as superseded by D-42). Not proposed here.
- Accept a handover every ~200k of context for launched hubs.

## Measured saving (from the research note)

- Cache reads above 200k context: mission-control era $607 (17% of $3,478),
  full history $4,072 (28% of $14,420).
- Seven long-running hub, tower and orchestrator sessions at 1M context cost
  $5,593 over the full history (39%).
- A handover costs about $0.45 on average (cold start plus first ten turns'
  writes), so it pays back within a few turns at high context.
