# Seed brief: amend `mission-control` (supervisor overhead and cost tiering, W21)

Captured 2026-11-09 by the performance and token-spend flight. Behaviour is
unchanged by this note; it is the proposal for sign-off. Owner of W40 (cost
per session in the panel) is the mc-fixes program; this note supplies the
measurement it needs and does not build the panel.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend mission-control

## The overhead, measured

From `docs/research/token-spend-2026-11.md` (mission-control era, 2026-11-05
to 2026-11-08, about 3.3 days, $3,478 total, about $1,050 a day):

- Mission-control hub sessions: $1,153 (33%), about $350 a day.
- Sessions the hubs launched: $2,202, of which sub-agents $1,057.
- Sessions neither ran nor launched: $123.

The laptop's relayed figure of about 60% for supervisor overhead is not
reproduced here: this host's transcripts give 33% for the hubs alone. The
laptop's per-session spend record (`spend-record.sh read --program planwright`)
is the measurement that settles it.

## The change (W21's items)

1. A one-knob cost-aware profile that sets the tier knobs together.
2. A separate `mission_control` model key. Today `kind_row` maps both tower
   and mission-control to `orchestrate_dispatch`, so one knob moves both.
3. A walk kind, so walks stop sharing the offload key.
4. A read-only allocation resolve verb (`allocation-apply.sh plan` writes
   ledger rows today).
5. A tower-comms doctrine line on batching and no acknowledgements between
   mission-control sessions.
6. A review of the `mission_control_tick_cadence` default (`5m`). Prompts are
   events now, so a periodic tick may be too frequent; the note does not set
   a new value.

## Decision for the operator

Which items ship in the next flight, and the cadence value once prompts are
events.
