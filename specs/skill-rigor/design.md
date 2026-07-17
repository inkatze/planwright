# Skill rigor — Design

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: `N` — new decision, minted in this bundle's drafting
session (2026-07-16).

## Decision log

### D-1: Mechanism altitude — no new rule doc  (N)

**Decision:** The rigor principles this spec applies live at mechanism
altitude: each lands as skill or script mechanism citing the doctrine
impulse that already governs it (the autopilot-reflex "prefer a mechanical
tool over LLM judgment" step, the meta-spec's cite-derived-figures rule,
validation-rigor's reproduction discipline). No new rule doc is minted and
no existing one is extended. This is the altitude record for the three
pinned seed claims (see the altitude-claim entries in `## Sources`).

**Alternatives considered:**
- Mint a sign-off-verification rule doc (or extend validation-rigor) and
  have skills cite it thinly. Rejected because: the impulses already have
  doctrine homes — a new doc would restate them at a second address; and
  doctrine prose front-loaded by skills counts against the same start-load
  budgets this spec is already squeezed by.
- Fold the verification rules into spec-format's sign-off-record section.
  Rejected because: the meta-spec is a protected doc with its own recorded
  growth concern, and the rules govern skill behavior, not bundle format.

**Chosen because:** designing at the wrong altitude was the exact failure
the gate exists to catch; here the honest answer is that the doctrine layer
is complete and the mechanism layer is what fell short — every seed
documents a skill not doing what doctrine already implies.

### D-2: `/self-review` resolves through the status render  (N)

**Decision:** Re-source the no-arg fallback rung from the stored-status
grep to the status render (`scripts/spec-status.sh`), accepting a spec
whose reported status is Ready or Active; and when the branch convention
names a spec that has no `kickoff-brief.md` of its own, treat the brief as
absent rather than falling through to a different spec's brief.

**Alternatives considered:**
- Widen the existing grep to `Status: Ready|Active`. Rejected because: it
  stays version-blind in spirit (a v2 bundle's derived Active and a v1
  stored Ready are indistinguishable to a grep) and leaves a second
  status-reading idiom in the codebase beside the render.
- Leave the rung Active-only. Rejected because: every format-version-2
  bundle stores Ready while work is in flight, so the rung is dead code
  against v2 and blind to signed-but-unstarted v1 bundles.

**Chosen because:** invariant-tasks Task 7 already re-sourced `/resume` to
the render as the canonical read surface; following the same pattern keeps
one status-reading idiom and is version-agnostic by construction. Multiple
Ready-or-Active candidates make the rung ambiguous, which degrades to the
existing ask-when-attended / proceed-brief-less arm rather than a guess.

### D-3: Two-layer CI gate on the sign-off, bounded wait  (N)

**Decision:** `/spec-kickoff` gains two verification layers around the
flip: (1) before the Draft→Ready flip, run the repository's lint over the
kickoff brief and every spec file the walkthrough edited, blocking the flip
on errors; (2) before the terminal `gh pr ready`, verify the head SHA's
check rollup is green, polling within a bounded wait (default ten minutes,
config-overridable), and on red or timeout leave the PR draft and surface
the remedy. The rollup query is pinned to the head commit's
`statusCheckRollup` (checks on the SHA, never PR review states — an
errored or stale review can masquerade as done).

**Alternatives considered:**
- Remote rollup only. Rejected because: every lint failure would cost a
  push-fix-push round trip that a local pre-flip lint catches in seconds.
- Local lint only. Rejected because: it covers the observed PR #128 class
  (markdownlint red) but not test or guard failures CI would catch.
- Check once, no wait. Rejected because: CI rarely completes within the
  seconds after a push, so nearly every kickoff would end "left draft,
  check later", relocating the burden back onto the human — the exact
  autopilot-reflex step-3 failure.

**Chosen because:** the two layers cover both observed failure classes at
their cheapest interception points, and the bounded wait keeps the gate an
automation, not a new polling ritual for the human.

### D-4: Recorded claims are re-derived, not trusted  (N)

**Decision:** The sign-off prefers the meta-spec's cite-derived-figures
rule (record the source, not the figure). Where the brief does record a
cross-check or numeric claim as evidence — per-tag coverage tallies, ID and
edit counts, pinned version figures, "every X cited by at least one Y"
assertions — `/spec-kickoff` re-derives it mechanically (the same command
family the sweep tooling uses) before the flip, and a mismatch blocks.

**Alternatives considered:**
- Keep trusting the lens-pass narrative. Rejected because: two verifiable
  defects shipped past a sign-off exactly this way on autopilot-reflex.
- Forbid recording figures outright. Rejected because: some evidence is
  irreducibly numeric (a coverage tally in a sign-off record); the useful
  rule is cite where possible, re-derive what is recorded.

**Chosen because:** a comparator command cannot be pencil-whipped; an
instruction an LLM follows can (autopilot-reflex step 5).

### D-5: Delta-scoped lens at mid-walk meaning edits  (N)

**Decision:** When `/spec-kickoff` applies an agent-authored meaning-class
edit during the walkthrough, a delta-scoped lens pass runs at the point of
application and its disposition is recorded in the brief section that
carries the edit. The terminal sign-off lens pass is unchanged.

**Alternatives considered:**
- Terminal lens only (status quo). Rejected because: a self-introduced
  spec bug propagated through four brief sections before the terminal pass
  caught it (the prompt-hygiene deadlock).
- Full-bundle lens after every edit. Rejected because: disproportionate;
  the risk is scoped to the edit and what depends on it.

**Chosen because:** the cost of a scoped pass is minutes; the cost of a
propagated spec bug is a rework of every section built on it.

### D-6: Post-lens stale-reference sweep before the anchor  (N)

**Decision:** After the sign-off lens pass mints or re-scopes any REQ,
`/spec-kickoff` sweeps the bundle and the earlier brief sections for
now-stale references — counts, cross-references, dependent task and test
wording, risk-IDs — and reconciles them before computing the anchor.

**Alternatives considered:**
- Rely on the lens pass itself to spot stragglers. Rejected because: the
  lens reviews the delta, not every earlier section's references to it;
  three stragglers from one root cause reached the review gauntlet this
  way on orchestration-concurrency.
- Leave stragglers to the downstream review gauntlet. Rejected because:
  that converts zero-cost sweep fixes into review-cycle amendments.

**Chosen because:** the sweep is mechanical (grep for the minted and
re-scoped IDs and the figures they change) and runs once, at the only
moment new-REQ staleness can exist but the anchor does not yet seal it.

### D-7: `/spec-draft` self-critique is an inline scoped lens  (N)

**Decision:** `/spec-draft`'s review-and-validate phase gains a scoped,
inline self-critique lens pass over the freshly assembled bundle, run
before the validator and before commit; findings are fixed in place or
surfaced to the human, and the pass is proportional — inline, not a
fan-out.

**Alternatives considered:**
- Full Discovery-Rigor fan-out per draft. Rejected because: the bundle is
  Draft-status output that `/spec-kickoff`'s full lens pass re-reviews at
  activation; duplicating the fan-out spends the rigor budget twice.
- No self-critique (status quo). Rejected because: an 86-raw/42-valid
  kickoff lens yield over a fresh draft shows cheap catches sitting one
  stage right of where they could land.

**Chosen because:** proportionality — the pass shifts cheap catches left
without duplicating kickoff's heavyweight review, matching the declared
scoping rule that lighter passes suffice where a human review follows.

### D-8: Adopt the self-location arm from the fix branch  (N)

**Decision:** Land the existing `fix/resolve-rule-doc-self-locate` work:
a final, lowest-precedence core arm resolving `<script-dir>/../doctrine/`,
additive after the `PLANWRIGHT_ROOT` / `CLAUDE_PLUGIN_ROOT` / writer-root
arms, with the branch's tests and doc alignment; the branch's own fragment
(obs:29f05039) is consumed as part of the landing.

**Alternatives considered:**
- Export/propagate the plugin root into dispatched worker subshells.
  Rejected as the primary fix because: it relocates the burden onto every
  dispatch path remembering to export, and one forgotten path reproduces
  the bug; self-location is intrinsic to the script being run.
- A cwd-walk arm (walk up from `$PWD` looking for `doctrine/` plus
  `plugin.json`). Rejected because: equivalent coverage to script-dir
  self-location for every observed case, but new code where a tested
  implementation already exists, and `$PWD`-dependent behavior is subtler
  than `$0`-dependent behavior.

**Chosen because:** the invoked script's own location is the one signal
present in every delivery mode (repo checkout, worktree, plugin cache,
writer install), the arm is additive so no env-root case can regress, and
the sibling resolver scripts already self-locate this way.

### D-9: Budget compliance is gated in Done-when  (N)

**Decision:** Tasks touching the `/spec-kickoff`, `/orchestrate`, and
`/self-review` prose carry `check:instructions` green on the touched
surface in their `Done when:`, making the instruction-headroom cross-spec
dependency agent-evaluable: the task cannot complete until headroom relief
lands or a genuine compensating trim fits the change.

**Alternatives considered:**
- Compensating trims only, no cross-spec dependency. Rejected because:
  spec-kickoff has seven words of headroom against four new mechanisms;
  compression at that ratio breaks prose meaning (the diet-reflow lesson).
- A prose dependency note only ("wait for instruction-headroom").
  Rejected because: not agent-evaluable; a worker cannot check a sibling
  spec's intent, but it can run `check:instructions`.

**Chosen because:** the budget guard is the mechanical form of the
dependency — it fails exactly until the precondition (relief or trim) is
true, whichever arrives first.

### D-10: Exit 3 is a clean hold, documented where exits live  (N)

**Decision:** `/orchestrate`'s selection section and stop-conditions table
document selector exit 3 (the format-version-2 transient evidence hold) as
"report the hold and end the step cleanly" — the same shape as lock
contention, not a halt — and the ready-task candidacy prose gains the
version-keyed sentence (v1 and v2 candidacy each stated).

**Alternatives considered:**
- Treat exit 3 as a stop-condition halt to Awaiting input. Rejected
  because: the hold is transient by design (evidence settling); parking
  the unit would convert a self-resolving wait into a human unblock.
- Renumber or fold exit 3 into exit 2. Rejected because: the selector's
  exit contract is shipped and consumed; the doc must follow the code.

**Chosen because:** the skill text is the single-tower operator's contract;
an unmapped exit reads as a hard failure, which is precisely the observed
misread the fragment records.

## Cross-cutting concerns

- **Budget walls.** Every prose-touching task is bounded by
  `check:instructions` (D-9). The three near-wall surfaces at drafting
  time: `skills/spec-kickoff/SKILL.md` at 4,243/4,250 words,
  `/orchestrate` start-load at 19,997/20,000, `/self-review` start-load at
  9,993/10,000. The instruction-headroom spec (sibling branch, in
  drafting) is the expected relief; its landing order relative to this
  spec's tasks is deliberately unconstrained beyond the Done-when gate.
- **Proportionality.** The new rituals are scoped to where the risk was
  observed: the mid-walk lens fires only on agent-authored meaning-class
  edits, the draft self-critique is inline (not fan-out), the sweep runs
  only after the lens mints or re-scopes REQs.
- **Security posture.** No new trust surface: the self-location arm reads
  a path derived from `$0`, not from input; the CI gate reads GitHub state
  via `gh`, already a degradation-managed dependency.
