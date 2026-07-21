# Kickoff verification passes and gates

Verification passes and gates the `/spec-kickoff` flow runs: the walkthrough's
mid-walk lens and post-lens stale-reference sweep, the sign-off lens review, and
the terminal spec-PR ready-flip CI gate. The skill names each at its point of
use and follows the mechanics recorded here; lifting the heavy mechanics out of
the skill body keeps `skills/spec-kickoff/SKILL.md` within its instruction
budget while the full rule stays authoritative in one place. (The pre-flip lint
and recorded-claim re-derivation, REQ-B1.2 / REQ-B1.3, stay documented inline in
the sign-off flow; this doc covers the passes and gates whose mechanics are
heavy enough to lift out.)

## Mid-walk delta-scoped lens (REQ-B1.4, D-5)

When `/spec-kickoff` applies an agent-authored meaning-class edit during the
walkthrough, a delta-scoped lens pass runs at the point of application — not
deferred to the terminal sign-off pass. In the status-quo terminal-only flow a
self-introduced spec deadlock propagated through four brief sections before the
terminal pass caught it (D-5); the mid-walk pass catches it at application.

- **Scope.** The edit's delta and what depends on it — proportionate, not a
  full-bundle re-lens (a full re-lens after every edit is disproportionate; the
  risk is scoped to the edit).
- **Disposition.** The pass's finding disposition is recorded in the brief
  section carrying the edit.
- **Erroring pass.** A lens pass that errors is surfaced, never treated as
  clean.
- **Terminal pass.** The terminal sign-off lens pass is unchanged and still
  runs; the mid-walk pass is additive.

## Post-lens stale-reference sweep (REQ-B1.5, D-6)

After any walkthrough lens pass (mid-walk or terminal sign-off) mints or
re-scopes a REQ, sweep the bundle and the earlier brief sections for now-stale
references and reconcile them before the anchor is computed. The lens reviews
the delta, not every earlier section's references to it, so stragglers (three
from one root cause on a past bundle) otherwise reach the review gauntlet as
review-cycle amendments.

- **Targets.** Now-stale counts, cross-references, dependent task and test
  wording, and risk-IDs.
- **Ordering vs the D-4 re-derivation.** The sweep completes before the
  recorded-claim re-derivation is finalized (REQ-B1.3, D-4): figures the sweep
  changed are re-derived.
- **Mechanical, once.** Grep for the minted and re-scoped IDs and the figures
  they change; the sweep runs once, at the only moment new-REQ staleness can
  exist but the anchor does not yet seal it.

## Sign-off lens review — scope and fan-out (REQ-A3.3, D-45)

The sign-off lens review is a Discovery-Rigor review of the bundle — the last
line of defense against spec bugs execution feedback cannot catch (D-45).

- **Scope.** Full bundle at first activation; delta-scoped at re-walkthroughs
  and amendments; skipped for expression-only changes (REQ-A3.3).
- **Fan-out.** One read-only sub-agent per canonical lens for any non-trivial
  delta per `discovery-rigor`; walk inline only for small, narrow deltas, and
  declare the path taken.
- **Lens-coverage table.** Emit the canonical lens-coverage table.

### Kickoff-specific altitude check (REQ-H1.3)

A check item within the sign-off lens review, not a new lens (the
`discovery-rigor` list is untouched). Determine **bundle-locally** whether
drafting fired an altitude trigger, from the pinned seed claims in
`requirements.md`'s `## Sources` section (never drafting-session memory); per
`autopilot-reflex`, a present altitude D-ID is the record a trigger leaves.

- **Triggered bundle.** Verify the altitude D-ID exists, is cited from the
  bundle's goal, and that the task decomposition matches the claimed altitude (a
  doctrine-first bundle with only mechanism tasks is a finding).
- **Untriggered bundle.** Needs no altitude record (per `proportionality`):
  record not-applicable.

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
