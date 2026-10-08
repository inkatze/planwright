# Seed brief: amend `fleet-hardening` (a tower permission floor that does not depend on the launch)

Captured 2026-10-07 during the `fleet-messaging` supervision amendment's
drafting session, which routed this work here rather than absorbing it:
the tower's permission posture is `fleet-hardening`'s tower self-governance
(its REQ-C group), a different interface and decision space from the
messaging transport.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend fleet-hardening

The bundle derives **Done**, so extending it triggers the reopen cycle
(stored Ready → Draft on all four headers); the scoped kickoff of the delta
flips it back. Append new REQ/D-IDs, never renumber.

## The gap

A tower started with plain `claude` plus `/planwright:tower` gets neither
the tower deny list nor the tower command guard, because both arrive only
through `--settings config/tower-settings.json` (obs:6be13a0c). The tower
skill's bring-up posture check cannot see which `--settings` file a
session was launched with, so in the documented launch it reports every
shipped deny entry missing and fails closed falsely (obs:48faa6b7). And the
tower settings allow Edit and Write outright, so `/tower`'s non-authoring
rule rests on skill prose alone (obs:ce918748).

## Proposal to evaluate (from obs:6be13a0c)

A plugin-wired UserPromptSubmit hook marks the session id as a tower when
`/planwright:tower` runs, and a plugin-wired PreToolUse entry (Bash and the
GitHub MCP write tools) applies `scripts/policy-guard.sh` in its tower tier
to marked sessions, reading the deny list from `tower-settings.json` rather
than a copy, so the posture check can accept plugin enforcement. Whether
the tower tier covers the whole tower-settings deny list is unverified, and
is the first thing the drafting session should establish.

## Observations

obs:6be13a0c rides an observations PR that was unmerged when this note was
written; obs:48faa6b7 and obs:ce918748 are on main. All three stay live for
this extension to consume.
