# The Autopilot Reflex

**A recurring ritual that fires only when a human remembers it is a doctrine
gap.** planwright's north star is that the human keeps the reserved controls
and planwright flies the rest; a ceremony that survives on human memory
violates it twice — the machine is not flying what it could, and the human's
attention is spent on remembering instead of judging. The autopilot reflex is
the six-step thought process for closing a ceremony gap of this shape. The
steps are the durable, reusable asset; any one mechanism they produce (a
release workflow, a required check, a publish script) is repo-local and
disposable by comparison.

Citations: autopilot-reflex REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
REQ-A1.5 · autopilot-reflex D-1, D-2, D-11.

## The six steps

Walk them in order; each step constrains the ones after it.

1. **Name the irreducible human gates first.** Before designing any
   automation, enumerate the acts that stay human: judgment calls, and
   reserved, irreversible, or externally-visible acts (sign-off, merge,
   publish). These stay human *and conscious* — a gate the human rubber-stamps
   without deciding is not a gate. Everything not named here is a candidate
   for automation.

2. **Automate up to the gates, never through them.** The machinery carries
   the work to the gate's edge — detection, preparation, verification,
   proposal — and stops. It never crosses a gate on the human's behalf, and
   never softens one into a default-yes (an auto-approve, a timeout-merge, a
   bypass flag). If step 1 named the gate correctly, everything short of it
   is fair game.

3. **Verify the burden was eliminated, not relocated.** A step a human must
   remember to *initiate* is not closed. Replacing "remember to cut a tag"
   with "remember to run the tag script" relocates the memory burden; the gap
   is closed only when the remaining human act is a response to something the
   system put in front of them, never a ritual they must recall unprompted.

4. **Surface by push or forcing-function, never by pull.** The system brings
   the pending act to the human — a standing PR that embodies the proposal, a
   red required check that blocks until the act happens, a notification on a
   state transition. Anything that requires the human to poll a dashboard,
   re-run a status command, or "check whether a release is due" fails this
   step: polling is the memory burden of step 3 wearing a different coat.

5. **Right-altitude every piece.** Place each part of the solution on the
   altitude ladder — impulse/doctrine (a rule about how to think, owned by the
   framework), capability (a seam the framework offers), mechanism (a concrete
   tool or workflow filling that seam), local value (one repo's configuration
   of it) — and resist promotion and demotion: a mechanism written into
   doctrine rots, and doctrine buried in a script is invisible. Where a piece
   requires no judgment, prefer a mechanical tool over LLM judgment: a
   comparator script cannot be pencil-whipped; an instruction an LLM follows
   can. The capability-vs-style boundary call this step keeps forcing is the
   [customization-boundary](customization-boundary.md)'s territory.

6. **Capture the reasoning as the reusable asset.** Record why the gates are
   where they are, which alternatives lost and why, and what the tradeoffs
   were — in doctrine and design decisions, not in session memory. The next
   ceremony gap will have different mechanics; only the captured reasoning
   transfers. A closed gap whose rationale evaporated with the session will
   be re-derived, wrongly, later.

## Altitude triggers

Step 5 has a failure mode upstream of design: a deliverable gets solutioned
at the wrong altitude because nobody asked which altitude it belonged at. Two
trigger classes catch this during spec work:

- **Seed claims** — explicit statements in an invocation or seed about the
  deliverable's nature: "that's a doctrine gap", "this is a first-class
  concern", "we keep doing X manually". A claim of this shape is an altitude
  assertion, and it is easy to under-weight in the rush toward mechanism.
- **Mid-flow signals** — moments during elicitation or design that reveal an
  unresolved altitude question: recurring capability-vs-style calls, an "is
  this even core?" hesitation, a mechanism acquiring rules that read like
  doctrine.

When a trigger fires during spec work, the deliverable's altitude MUST be
resolved before proceeding to solution design. Designing first and
retrofitting the altitude is how a doctrine deliverable ends up specced as a
one-repo script.

## The phase re-anchor

A correct altitude call at the start does not survive a long session on its
own; drift is gradual and self-concealing. So each phase-end running summary
during drafting restates the claimed altitude and flags any gap between the
claim and what the elicitation is currently producing ("the seed claimed
doctrine; the last hour produced only mechanism tasks"). The restatement is
cheap; its absence is how a session that opened with "that's a doctrine gap"
spends itself on solutioning and only circles back to the doctrine at the
end.

## The altitude record (trigger-scoped)

When an altitude trigger has fired, the resulting bundle MUST record the
altitude call as an early design decision — an **altitude D-ID** — cited from
its goal. The D-ID is what downstream checks can verify (a kickoff lens pass
can confirm a triggered bundle carries it and that the task decomposition
matches it); a conversational resolution with no artifact can be
pencil-whipped. When no trigger fired, no record is required: per
[proportionality](proportionality.md), the ceremony is scoped to the specs
that exhibited the risk, and a trivial bundle pays nothing.

## Wiring

The authoring skills operationalize the discipline the way research-rigor is
already wired (D-11): `/spec-draft` pins seed claims during seed gathering,
resolves altitude before design when a trigger fires, and restates the
claimed altitude in every phase-end summary; `/spec-kickoff`'s lens pass
verifies that a triggered bundle carries the altitude D-ID cited from its
goal. The reflex itself stays skill-agnostic: any flow that closes a ceremony
gap — authoring or runtime — walks the same six steps.
