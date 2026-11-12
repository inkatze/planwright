# Seed brief: amend `custom-steps` with a machine-wide bound on heavy local runs

Captured 2026-11-09 at the mission-control Amendment 6 kickoff, from the
operator's decision relayed through the hub: leave the bound out of that
amendment and queue it as its own amendment (the operator's choice: "Leave
out, queue amendment"). It is walked in the same kickoff session as a
separate bundle, with its own question and its own sign-off record.

Suggested route: the same kickoff walks `custom-steps` as a delta on its
Active bundle (`/spec-kickoff specs/custom-steps`), the delta drafted from
this note once the operator confirms the shape.

## The conflict this resolves

`custom-steps` owns the rule. REQ-I1.5 and D-25 make the full local suite
join a pool only through the opt-in key `full_suite_pool`, whose core
default is empty, so a full suite runs unpooled. D-21 keeps the values in
overlays (capability in core, values in overlays), and REQ-I1.3 gives a
pool's capacity the core default 1 only once something names the pool. On a
host running several workers, nothing in core stops many full suites and
gates from running at once; the host has hit load high enough that the
operator holds heavy runs by hand. A machine-wide bound by default
contradicts the empty core default, so it is a meaning-class change to a
signed decision, not a value an overlay can set today without each adopter
finding the key.

`test-throughput` REQ-A1.1 and REQ-A1.2 already bound test files per host
(a machine-wide ticket pool sized by core count); they do not bound whole
runs (a full suite, a gate), which is what this asks.

## The change to draft

A full local suite run and every gate SHALL hold a slot of one shipped
machine-wide pool by default, its capacity a knob sized from the host
(cores and memory) with the machine-local layer able to override it, so
the default no longer leaves heavy runs unpooled. Open points for the
walk: whether the default pool is `full_suite_pool`'s shipped value or a
new key; how its capacity is derived; what an adopter with one checkout
sees (no change in practice); and how it composes with the per-file
ticket pool, so a nested run never waits on itself (REQ-I1.2's mark rule).

## Why not mission-control

Mission control schedules work against the host budget (its REQ-M1.6) but
does not own how a suite or gate takes a slot; the pool and its default are
`custom-steps`'.
