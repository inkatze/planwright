# Kickoff verification gates

Verification gates the `/spec-kickoff` sign-off flow runs around the terminal
spec-PR ready-flip. The skill names each gate at its point of use and follows
the mechanics recorded here; lifting the heavy mechanics out of the skill body
keeps `skills/spec-kickoff/SKILL.md` within its instruction budget while the
full rule stays authoritative in one place. (The pre-flip lint and
recorded-claim re-derivation, REQ-B1.2 / REQ-B1.3, stay documented inline in the
sign-off flow; this doc covers the gates whose mechanics are heavy enough to
lift out.)

## Terminal ready-flip CI gate (REQ-B1.1, D-3)

Before the terminal `gh pr ready` (sign-off step 8), verify the spec PR's CI on
its **head commit** and mark the PR ready only on a genuine pass. The gate is
skipped cleanly when the upstream no-remote/no-PR degradation arm (sign-off
step 7) has already fired.

- **Rollup query, pinned to the head SHA.** Query the head commit's
  `statusCheckRollup` (`gh pr view <spec-PR> --json
  statusCheckRollup,headRefOid`) — checks **on the SHA**, never PR review
  states, which an errored or stale review can masquerade as done.
- **Positive green.** Flip only on **at least one completed check and overall
  success**; an empty rollup is not success.
- **Bounded wait, bounded cadence.** CI rarely reports within seconds of the
  push, so poll within a bounded wait (`kickoff_ready_ci_wait`, default `10m`,
  read at pre-flight step 4; a malformed value falls back to the default with a
  warning) at a bounded cadence — tens of queries per wait, not hundreds.
- **Head re-pin (the R3 mid-wait head-movement rule).** Re-confirm head
  identity immediately before `gh pr ready`: a `headRefOid` that moved during
  the wait refuses the flip.
- **Refusal arm.** On **red, empty, unresolved, a query failure, an expired
  wait, or a moved head**, leave the PR draft and record the pending ready-flip
  in the spec's `tasks.md` `## Awaiting input` section — the re-entry point, so
  a re-run completes only the flip. The entry names the pending flip and the
  **neutral failure class only**; full remedy detail stays operator-facing
  (`security-posture` data hygiene, per D-3).
