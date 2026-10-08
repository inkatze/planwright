# Seed brief: `tower-comms` as the home for the supervisor duty's queue mechanics

Captured 2026-10-07 during the `fleet-messaging` supervision amendment's
drafting session. That amendment states the supervisor duty as doctrine
(`fleet-messaging` REQ-G1.9, D-29, in the inter-orchestrator-coordination
doctrine): a tower stays its worker's operator until the work is finished,
answers what it can from the task, the spec, and the code, and relays to
the operator only forks and operator-only blockers, carrying the answer
back. It deliberately changes nothing in how a question that does reach the
operator is queued, settled, or delivered.

If running the duty shows the operator queue needs a change (for example a
kind or a settling reason for "answered by the supervising tower", or the
tower carrying an operator answer back to the worker as a tracked step),
that change belongs to `tower-comms`, which owns the operator queue, not to
`fleet-messaging`.

Suggested invocation, once there is evidence of a concrete queue change:

    /spec-draft --extend tower-comms

Seed observation: obs:fc7fe636 (cited, not consumed, by `fleet-messaging`).
