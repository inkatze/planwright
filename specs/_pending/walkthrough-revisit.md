# Seed: revisit (rethink or retire) `/spec-walkthrough`

Captured 2026-07-17 during the `operator-dialogue` drafting session. A seed for a
future `/spec-draft` (scoped amendment to the Done `spec-comprehension` bundle, or
a decision to retire the command). Run fold-detection against `spec-comprehension`
(owner of `/spec-walkthrough`) and `operator-dialogue` before assuming a shape.

## The problem

Operator feedback (2026-07-17): `/spec-walkthrough` "didn't work at all." It was
not intended to be on-demand only, and even on-demand it was not useful.

Diagnosis carried into `operator-dialogue`'s design (D-2): the walkthrough shipped
**out of band** — a separate command producing an HTML artifact the operator must
remember to generate and then open in a browser — and **on-demand only**, so it was
never present at the moment a decision was being made. Comprehension ceremony
nobody pays does not build comprehension. `operator-dialogue` bets the opposite
way: comprehension happens **in-band**, inside the live kickoff dialogue where the
operator already is.

## The open question for the revisit

Given `operator-dialogue` moves comprehension in-band at `/spec-kickoff`, does a
standalone read-only walkthrough still have a job?

- **Retire it** if in-band kickoff comprehension covers the need, and the only
  remaining use (archaeology on a finished/abandoned spec) is not worth a separate
  command + artifact.
- **Rethink it** if there is a real unaided-independent-read need that in-band
  guided dialogue cannot serve (the independence firewall's original motivation).
  If so, the redesign must fix the out-of-band failure: surface in-band, not as a
  browser file the operator must remember to open.

Do not pre-decide. The gate: revisit only after `operator-dialogue`'s kickoff
instantiation has proven the in-band model, so the walkthrough is re-decided
against a validated alternative rather than in the abstract.

## References

- `specs/operator-dialogue/` — the in-band-comprehension bet (D-2), the preserved
  independence firewall (D-3), and the deferral gate (`tasks.md` Deferred).
- `specs/spec-comprehension/` (Done) — the current `/spec-walkthrough` design and
  its independence-firewall rationale.
