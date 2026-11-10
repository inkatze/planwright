# Seed brief: amend `mission-control` and `fleet-lifecycle-closure` (end a worker rather than let it wait past an hour)

Captured 2026-11-09 by the performance and token-spend flight
(`docs/research/token-spend-2026-11.md`, cut 3). Behaviour is unchanged by
this note; it is the proposal for sign-off.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend fleet-lifecycle-closure

(then the same for `mission-control`, which owns the wait helpers.)

## The change

A wait expected to outlast 55 minutes ends the worker. It writes its handover
brief and exits; mission control launches a fresh worker with that brief when
the awaited event fires. The shipped wait helpers and the worker brief carry
the rule.

## Why 55 minutes

The 1-hour cache lifetime. Past it, a resumed worker rebuilds its whole
context at the write rate.

## Measured saving (from the research note)

- Cache rebuilds after an idle gap over an hour: mission-control era 109
  rebuilds, 23.7M tokens, $171; full history 428 rebuilds, 131M tokens, $1,093.
- Saving if the rule had applied: about 18M tokens and $125 (era), and 107M
  tokens and $895 (full history).
- A fresh session with a handover brief starts for about $0.42; the average
  rebuild writes 217k tokens ($1.57).

## Decision for the operator

Accept a fresh-worker relaunch (with its brief) after any wait past 55
minutes, in exchange for these rebuild costs. Waits that are short stay as
they are.
