# Seed brief: amend `merge-currency-guard` (the deterministic PR-ready attention record)

Captured 2026-08-18 during the `fleet-lifecycle-closure` drafting session,
which routed this work here rather than absorbing it (that bundle's D-9).

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend merge-currency-guard

The bundle derives **Active** (Tasks 1–2 merged, Tasks 3–4 outstanding), so
extending it leaves the stored status untouched: the delta is Draft content
inside an Active bundle, and `/spec-kickoff`'s delta re-walkthrough is the
sign-off path. No reopen cycle.

## Why this is an amendment and not a new bundle

`doctrine/fleet-coordination-floor.md` assigns it by name. Its
scope-boundary section lists, among adjacent mechanisms that keep their own
owners:

> **The deterministic PR-ready-push mechanism** — the planned
> `merge-currency-guard` spec, which owns the ready-surface interception that
> mechanism shares with its stale-flip guard.

And the deterministic-attention floor itself says the mechanism realising it
"is owned by the planned `merge-currency-guard` spec and is cross-referenced,
not implemented, by the bundle that records this floor". The ownership claim
is doctrine, not inference.

## The gap (obs:bfc6faf0)

"PR verified-ready-for-the-human's-merge" has **no deterministic push path**.
It reaches the human only via an LLM tower polling GitHub and calling a
notification by hand — brittle by design, and it failed live: ready
PRs #282/#283/#284/#285 went un-pushed, and #277/#281 were missed
proactively.

The infrastructure is half-built already, which is what makes this a small
delta rather than a new mechanism:

- `fleet-liveness.sh` plus the `Notification` hook already push worker
  awaiting-input deterministically to `fleet-attention.sh`.
- `fleet-attention.sh` already **models** a `pr-ready` worker state.

Two things are missing:

1. **Nothing fires `pr-ready` deterministically.** No hook maps a worker's
   `gh pr ready` or the MCP draft→ready flip to an attention heartbeat.
2. **`pr-ready` is classified non-actionable.** Only `awaiting-input` drives
   the decision queue and the notification push, so even a fired record would
   sit silent.

## Why it belongs with this bundle specifically

Task 2 already shipped `scripts/ready-guard.sh`, a deny-emitting PreToolUse
hook intercepting **both** draft→ready surfaces — a Bash matcher for
`gh pr ready` and an MCP matcher for `update_pull_request`. That is precisely
the interception point the attention record needs. The observation predicted
this convergence: the fix is "a PostToolUse guard on `gh pr ready` / the MCP
ready path, **sibling to the merge-currency ready-guard idea — both intercept
the same two ready surfaces**".

So the delta reuses a shipped surface rather than adding one.

## Shape of the delta

- A deterministic emission of a `pr-ready` attention record at the ready-flip
  surfaces `ready-guard.sh` already covers — as a PostToolUse sibling, or
  folded into the existing hook's success path. Decide which during the delta
  walkthrough; the hook already carries the matchers and the payload parsing.
- Reclassify `pr-ready` as **actionable** in `fleet-attention.sh`, so it
  enters the decision queue and drives the notification seam. It is a
  reserved-human moment (the merge), which is the definition of actionable.
- Keep tower polling strictly as the fallback, never the sole path — the
  deterministic-attention floor's exact wording.
- Respect the never-auto-merge floor throughout: this surfaces a merge-ready
  PR to the human, and merges nothing.

## Interaction with the existing REQs

`merge-currency-guard` REQ-A1.4 explicitly declines to mandate that the
ready-flip be automatic, and REQ-A1.3 keeps enforcement agnostic to which
party issues the flip. Neither conflicts: this delta is about **surfacing**
that a flip happened, not about causing one. Confirm that reading at the
delta walkthrough — if it reads as contradiction rather than complement, that
is meaning-class drift and needs a new REQ rather than a reinterpretation.

## Sequencing note

Tasks 3–4 are outstanding. Task 4 is the adversarial suite over the guard's
decision matrix; if the attention record rides the same hook, the delta's
tests should join that suite rather than forming a parallel one. Consider
sequencing the delta after Task 4 so the matrix is stable, or explicitly
folding the new cells into it.

## Fold-detection note

Run it anyway, but the 2026-08-18 pass already checked `fleet-autonomy`
(derives Done; shipped the attention store and the liveness hooks this
consumes), `fleet-hardening` (derives Done; shipped the `Notification`-hook
attention signal), and `concurrent-orchestrator-coordination` (Active;
records the floor but explicitly cross-references rather than implements it).
