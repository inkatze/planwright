# Custom steps — Design

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle's drafting session
(2026-09-21 and 2026-09-22). Foreign IDs are namespace-qualified.

## Decision log

### D-1: Altitude — capability plus doctrine, mechanics in scripts, the gauntlet in an overlay  (N)

**Decision:** The deliverable is a core capability (named points, a step
catalog kind, one list key per point, resolved through the overlay layers)
governed by a rule doc (the point vocabulary, the step contract, the
reserved controls), with every mechanism in scripts and the operator's own
verification chain living in their overlay. Nothing about which review
tools run is baked into core.

**Alternatives considered:**
- Mechanism only: widen the nestable predicate to reach user commands.
  Rejected because: it keeps the single narrow seam and answers issue 393
  without issue 383; the next point an operator needs (post-pr, pre-ready)
  would need a second bespoke knob with its own resolution rules.
- Doctrine only: name the points and leave wiring to each operator's
  prompts. Rejected because: the seeds record the manual step as the most
  repeated and most forgotten one; a rule nobody's tooling runs is the
  ceremony the autopilot reflex exists to close.
- Ship the panel and Copilot passes as plugin skills. Rejected because: it
  pulls non-Anthropic backends and GitHub Copilot plumbing into core and
  bakes one operator's tools into every adopter's install, the exact cost
  the customization boundary names.

**Chosen because:** the altitude trigger fired on pinned seed claims ("the
general mechanism is missing", "narrow by construction"), and the reflex's
right-altitude step puts the ability to attach steps in a core seam, the
rules about what a step may do in doctrine, the runner in scripts where the
instruction budget does not charge it, and the specific chain in the
overlay where style belongs.

### D-2: Six wired points; the rest named and gated  (N)

**Decision:** This bundle wires `pre-implementation`, `pre-ci`,
`convergence`, `pre-pr`, `post-pr`, and `pre-ready-flip` in `/execute-task`
and `pre-spec-ready-flip` in `/spec-kickoff`. The orchestrator-side and
pipeline-side points from issue 383 are named in the rule doc and parked
under Deferred with a gate.

**Alternatives considered:**
- Wire every point in one bundle. Rejected because: it touches
  `/orchestrate`, whose instruction closure is measured at effectively zero
  headroom, and no seed records a need at those points yet.
- Wire only the pre-PR points. Rejected because: it leaves the Copilot loop
  manual, which is the gap the overnight-run observation recorded.

**Chosen because:** every seed fires on a unit point, and naming the rest
now means later wiring adds no new format.

### D-3: Where each point fires  (N)

**Decision:** In `/execute-task`: `pre-implementation` after pre-flight
passes and before the first implementation commit; `pre-ci` after the last
implementation commit and before the full CI run; `convergence` after CI is
green and the once-per-pass `main` sync, replacing the review chain in
place; `pre-pr` after the last convergence step and before the push;
`post-pr` after the draft PR exists and its body is assembled;
`pre-ready-flip` immediately before any agent-issued flip of a unit PR, on
the head to be flipped. In `/spec-kickoff`: `pre-spec-ready-flip` after the
push and PR step and before the terminal CI gate, so a step that pushes
moves the head the gate then checks.

**Alternatives considered:**
- Sync `main` before `pre-ci` so every step sees a current head. Rejected
  because: merge-currency-guard places the sync at the top of convergence,
  and moving it would make CI run on a head that convergence then moves
  again.
- `post-pr` before the body is assembled. Rejected because: a step that
  reads the PR (the Copilot loop reads its threads) needs the body present.
- Fire `pre-ready-flip` once per unit run like the other points. Rejected
  because: no flip happens inside a unit run today; the point binds the
  flip attempt, whoever issues it, and fires once per attempt.

**Chosen because:** each moment is one the skill already has as a step
boundary, so wiring is a one-line call at an existing seam.

### D-4: A catalog defines steps, a flat list per point orders them  (N)

**Decision:** Step definitions are entries in a `steps` data catalog
(scalar fields, the constrained catalog reader, merged by id across layers
with supersede). Each point's chain is one flat config key naming step ids
in order. The old nestability predicate is dropped; resolvability is the
test.

**Alternatives considered:**
- One flat key per point with an inline mini-grammar carrying every field.
  Rejected because: a bespoke parser and a syntax operators must learn,
  for a format the catalog reader already handles.
- Catalog only, ordered by declaration, overlays appending. Rejected
  because: an operator cannot place a step before a project's without a
  supersede, and interleaving is decided by layer order rather than by the
  operator.

**Chosen because:** the config reader is flat by design (a nested value in
the repo-tracked layer is a hard failure), the catalog reader already holds
structured entries with a merge rule, and separating "what a step is" from
"which run here, in what order" lets a user define a step once and every
project use it.

### D-5: Last layer wins per point, with a shadow warning  (N)

**Decision:** A point's list resolves exactly like every other config key.
The resolver additionally prints one warning naming each lower layer whose
list for that point was shadowed.

**Alternatives considered:**
- Union in layer order. Rejected because: a user could add but never
  remove or reorder a project step, and layer order would silently decide
  interleaving.
- An `_append` key per point. Rejected because: a second key per point to
  document and test, for a case a restated list in a higher layer already
  covers.

**Chosen because:** one rule to learn, fully deterministic, and the warning
closes the case the operator raised, a personal list silently overridden.

### D-6: The missing-step matrix  (N)

**Decision:** A declared step that does not resolve on the host is handled
by two axes. Attended: surface and wait, at every layer. Unattended: a
step from a repo-tracked list parks the unit before the point runs; a step
from an adopter or machine-local list is skipped with a warning and a skip
record. Resolution completes for the whole point before any step runs.

**Alternatives considered:**
- Stop and ask at every layer. Rejected because: the operator wanted the
  posture to depend on layer and attendance, and an unattended fleet
  stalling on one operator's missing personal tool is the flood the fleet
  work exists to remove.
- Skip and warn at every layer. Rejected because: it is the behavior that
  silently dropped the panel pass, and a team step is policy.

**Chosen because:** a project step is the team's policy of record and a
personal step is one operator's convenience; the blast radius of each
failure matches the layer's, which is the same reasoning the by-layer
malformed policy already records.

### D-7: Three hosting modes, defaulted from dispatch isolation  (N)

**Decision:** `isolated` launches a fresh session through the backend seam
at the step's tier; `continue` attaches to the immediately preceding step's
session in the same list, by its recorded session id; `in-session` runs in
the unit's own session. Unset hosting maps from `dispatch_isolation`. A
`continue` step on a backend without resume is a failed step, not a
degraded one. Model and effort resolve through the existing per-step
allocation knobs keyed on the step id.

**Alternatives considered:**
- Two modes only (fresh or in-session). Rejected because: the operator
  named the case of a step that needs the previous step's context but not
  the worker's, and both session-grade backends already persist and resume
  session ids.
- Degrade `continue` to `isolated` and record it. Rejected because: a step
  declared to build on prior context would run without it, which the
  operator's stop-and-ask preference forbids; recording a substitution is
  not the same as running what was declared.
- A compound step type sharing one session across several actions.
  Rejected because: it breaks one-session-per-step and muddies the exit
  contract; `continue` gives the same effect as a sequence.

**Chosen because:** the seam already exists (per-step sessions, resume by
id, the open step-type key space), so the modes are a declaration on top
of it rather than new machinery.

### D-8: Outcomes are host-classified from the handoff  (N)

**Decision:** Four outcomes: `passed`, `applied`, `halted`, `failed`. A
command step's outcome is its exit code. A skill or prompt step's outcome
is classified by the hosting session from the step's handoff, with the
excerpt it judged from written into the record. Failure posture is per
step, `halt` by default.

**Alternatives considered:**
- Require every step to emit a machine-readable result block. Rejected
  because: the operator's existing review commands would each need
  changing before they could be steps, and the doctrine already has the
  host classify the review chain's exits.
- Exit code only, with session steps always passing. Rejected because: a
  review step that found nothing would be indistinguishable from one that
  never ran properly.

**Chosen because:** it is what `/execute-task` does today for the review
sequence, made explicit, enumerated, and recorded.

### D-9: Mechanics in scripts and one point-of-use rule doc  (N)

**Decision:** Resolution, the missing-step decision, record writing, and
record rendering live in scripts. The vocabulary and contract live in one
rule doc, `doctrine/custom-steps.md`, loaded at point of use by
`/execute-task`. Each skill carries a one-line call per point, funded by
trimming the review-sequence prose it replaces; `/spec-kickoff` gets only
the script call.

**Alternatives considered:**
- Describe the runner in skill prose. Rejected because: the audit measures
  `/execute-task` nine words above its floor and `/spec-kickoff` fourteen,
  with kickoff's closure thirty-three words from its pinned margin.
- Raise the budgets. Rejected because: the headroom ladder puts a raise
  after diet and reclassification, and both are available here.

**Chosen because:** scripts are not instruction surfaces, the existing
declared exceptions require a compensating trim in the same change, and
the convergence section being replaced is the trim.

### D-10: Replace the review-sequence knob outright, warn on the old key  (N)

**Decision:** `review_sequence` is removed from the core defaults, its
resolver deleted, and its every non-spec surface updated; the repo's own
value migrates in the same change. A stale key at any layer produces one
warning naming the layer and the new key, and is ignored.

**Alternatives considered:**
- Alias then retire (the drafter's recommendation). Rejected because: the
  operator chose a single spelling now over a deprecation window; the
  warning keeps the removal from ever being silent.
- Keep both indefinitely. Rejected because: two spellings and a precedence
  rule between them, forever.
- Hard-fail a repo-tracked stale key. Rejected because: it would block a
  whole team's units on upgrade day for a key that no longer does anything.

**Chosen because:** operator decision, recorded against the recommendation
so the tradeoff is visible: no adopter path is silently broken, and the
one warning is the migration instruction.

### D-11: The worker guard approves declared command targets  (N)

**Decision:** The allow-only worker command guard learns to approve a
command whose first token equals a declared command step's resolved target,
after the same charset and containment checks it applies to plugin scripts.
Declarations are read only from human-owned layers, and the worker profile
cannot write them.

**Alternatives considered:**
- Operator-maintained allow entries only. Rejected because: a forgotten
  entry stalls an unattended unit until the attention surface notices, the
  same shape as the permission flooding the guard was built to remove.
- Auto-approve any command a step names, without checks. Rejected because:
  the guard's containment and charset checks are what keep an allow-only
  hook from approving a hostile path.

**Chosen because:** the trust is already placed when a human writes the
declaration in a layer the worker cannot edit, and the guard is
deterministic with no model in the decision path.

### D-12: After post-pr, regenerate the record and verify the draft; never re-run  (N)

**Decision:** When a post-pr step moves the head, the runner regenerates
the PR body's audit record and pending-sign-off checklist from the final
range and verifies the PR is still a draft, parking the unit if it is not.
Earlier points are not re-run.

**Alternatives considered:**
- Re-run convergence on the new head until a pass moves nothing. Rejected
  because: unbounded cost and its own iteration cap and loop detection,
  when the ready-guard already refuses a flip on a stale or behind-base
  head.
- Do nothing after the step. Rejected because: the stale-checklist gap the
  seeds recorded stays open.

**Chosen because:** the checklist is a pure function of the range, the
regeneration is cheap, and the operator's stated wish is fewer re-runs and
re-syncs, not more.

### D-13: A separate spec-PR flip point, plus a unit-kind field  (N)

**Decision:** `pre-spec-ready-flip` is its own list key, run by
`/spec-kickoff`. `pre-ready-flip` governs agent-issued unit-PR flips. Every
step's context carries the unit kind, so a step shared between the two can
also branch on it.

**Alternatives considered:**
- One point for both flips. Rejected because: the operator observed that
  spec PRs are prose-heavy and may want a different chain.
- Task PRs only. Rejected because: the spec flip is the one agent-issued
  flip that exists today, and leaving it outside the vocabulary means two
  flip paths with different rules.

**Chosen because:** one key more buys a distinct chain for the artifact
that most differs, and the kind field keeps a shared chain possible.

### D-14: A fixed context set, by environment and preamble  (N)

**Decision:** Ten fields, no more: spec, unit ids, unit kind, branch, base
branch, worktree path, PR number, point, step id, previous record path.
Environment variables for command steps, a preamble for session steps.
No context value is interpolated into a command line.

**Alternatives considered:**
- Add the running audit record's path. Rejected because: it couples steps
  to the record's format; the previous step's record path covers the
  chaining case.
- Four fields, steps derive the rest with git and gh. Rejected because:
  every post-pr step would rediscover the PR number on its own.

**Chosen because:** a stable, documented, testable surface that decouples
operator steps from planwright internals, and a channel a dispatched worker
can read (a shell variable did not reach one, obs:00dccd4e).

### D-15: Timeout and requires; no env or cwd fields  (N)

**Decision:** A step may declare `timeout` (seconds) and `requires`
(executables). It may not declare environment pairs or a working
directory.

**Alternatives considered:**
- An `env` field. Rejected because: it is where a secret would end up in
  committed config; a step reads credentials from the host environment.
- A `cwd` field. Rejected because: every step runs in the unit's worktree
  and no seed records a need.

**Chosen because:** the seeds record an external CLI hanging or returning
empty, which timeout and requires address, and the two rejected fields add
risk without a recorded need.

### D-16: Step records as an in-worktree cache, folded into the PR body  (N)

**Decision:** Records are written per step under the worktree's `.claude/`
cache directory, never tracked, and rendered as one table per point inside
the PR body's collapsed audit block.

**Alternatives considered:**
- Records under the fleet home. Rejected because: the PR-body assembly runs
  in the worker's checkout, and a unit run outside the fleet has no fleet
  home.
- Records in `tasks.md`. Rejected because: execution state is derived,
  never authored, under format-version 2.

**Chosen because:** the handover brief already establishes the worktree
cache as the home for per-run, non-authoritative state.

### D-17: Reserved controls and the no-recursion rule  (N)

**Decision:** A step never merges, flips ready, force-pushes, or rewrites
history; steps before post-pr never push; a step may not target a pipeline
entry skill. The worker denies and the ready-guard apply to steps as to
everything else.

**Alternatives considered:**
- Allow a step to flip ready when issue 379 lands. Rejected because: the
  flip is the act the pre-ready-flip point guards; a step is what runs
  before it, not the thing that performs it.
- Allow a step to dispatch a nested unit. Rejected because: it re-enters the
  pipeline from inside a unit, and the dispatch-entry disjointness rule
  exists to prevent exactly that.

**Chosen because:** the hard invariants are not weighable, and the
no-recursion rule preserves an existing guarantee by construction rather
than by a second enum.

### D-18: Serial only  (N)

**Decision:** Steps at a point run one at a time in list order. Parallel
steps are deferred behind a gate.

**Alternatives considered:**
- Parallel groups within a list. Rejected because: `continue` hosting and
  the pending-sign-off commit discipline both assume a linear history of
  steps, and no seed records a need.

**Chosen because:** determinism was the operator's stated requirement, and
a serial chain is the simplest thing that is deterministic.

## Cross-cutting concerns

- **Instruction budget.** Every skill edit this bundle makes lands with its
  compensating trim in the same change; D-9 is the mechanism. The
  execute-task closure has unpinned headroom for the new rule doc; the
  kickoff closure does not, so kickoff loads no new doc.
- **Worktree config visibility.** The machine-local layer does not reach
  workers in worktrees; the documentation names the adopter layer as the
  per-user layer that does. Fixing the gap belongs to
  customization-overlay.
- **Data hygiene.** Step records and PR-body tables carry no secrets;
  declarations have no environment field.
