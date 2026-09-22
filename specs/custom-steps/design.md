# Custom steps — Design

**Status:** Ready
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle's drafting session
(2026-09-21 and 2026-09-22); `K` = new decision, minted at the kickoff
walkthrough (2026-09-22). Foreign IDs are namespace-qualified.

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
- Reuse the host's own hook seam (Claude Code's tool-event hooks) as the
  attachment mechanism. Rejected because: those hooks fire on tool and
  session events, not pipeline moments, and cannot host a session-grade
  step; they remain the seam the guards use.

**Chosen because:** the altitude trigger fired on pinned seed claims ("the
general mechanism is missing", "narrow by construction"), and the reflex's
right-altitude step puts the ability to attach steps in a core seam, the
rules about what a step may do in doctrine, the runner in scripts where the
instruction budget does not charge it, and the specific chain in the
overlay where style belongs.

### D-2: The unit's points wired, the flip point defined, the rest named and gated  (N)

**Decision:** This bundle wires `pre-implementation`, `pre-ci`,
`convergence`, `pre-pr`, and `post-pr` in `/execute-task` and
`pre-spec-ready-flip` in `/spec-kickoff`; it defines `pre-ready-flip` in
the rule doc and binds it through REQ-E1.3 and REQ-E1.5, the first
in-repo unit-PR flipper wiring it, since `/execute-task` never flips. The
orchestrator-side and pipeline-side points from issue 383 are named in the
rule doc and parked under Deferred with a gate. The vocabulary is
core-owned: every point is a moment inside a skill only core can wire, so
an adopter's need for a new moment travels through an observation, not an
overlay.

**Alternatives considered:**
- Wire every point in one bundle. Rejected because: it touches
  `/orchestrate`, whose instruction closure is measured at effectively zero
  headroom, and no seed records a need at those points yet.
- Wire only the pre-PR points. Rejected because: it leaves the Copilot loop
  manual, which is the gap the overnight-run observation recorded.
- Let overlays declare new points. Rejected at kickoff because: a point
  with no skill call behind it is a list that never runs, the silent-skip
  shape this bundle exists to remove.

**Chosen because:** every seed fires on a unit point, and naming the rest
now means later wiring adds no new format.

### D-3: Where each point fires  (N)

**Decision:** In `/execute-task`: `pre-implementation` after pre-flight
passes and before the first implementation commit; `pre-ci` after the last
implementation commit and before the first full CI run of the unit run;
`convergence` after CI is green, resolved first, then the once-per-pass
`main` sync, then the steps, replacing the review chain in place; `pre-pr`
after the last convergence step and before the push; `post-pr` after the
draft PR exists and its body is assembled; `pre-ready-flip` immediately
before any agent-issued flip of a unit PR, on the head to be flipped. In
`/spec-kickoff`: `pre-spec-ready-flip` after the push and PR step and
before the terminal CI gate, whether or not the flip is configured to
follow, so a step that pushes moves the head the gate then checks.

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
(single-line scalar fields, the constrained catalog reader, merged by id
across layers with supersede). Each point's chain is one flat config key
holding an inline flow list of step ids in order, the empty list meaning
run nothing. The old nestability predicate is dropped; resolvability is
the test.

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
list for that point was shadowed, through a per-layer read mode the config
reader gains for it (its merged mode exposes only the winner).

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
by two axes, the resolver printing one token per step. Attended: `ask`,
surface and wait, for any overlay layer. Unattended: a step from a
repo-tracked list prints `park` and the unit parks before the point runs;
a step from an adopter or machine-local list prints `skip`, with a warning
and a skip record. A step from the core default list prints `park` at
both attendances. Attendance is passed explicitly by the hosting skill.
Resolution completes for the whole point before any step runs. Malformed
declarations take the by-layer policy instead: a malformed list value
degrades to the core default, a malformed entry is skipped with its id then
non-resolving, a malformed repo-tracked value or entry hard-fails, a
malformed core one is a broken install.

**Alternatives considered:**
- Stop and ask at every layer. Rejected because: the operator wanted the
  posture to depend on layer and attendance, and an unattended fleet
  stalling on one operator's missing personal tool is the flood the fleet
  work exists to remove.
- Skip and warn at every layer. Rejected because: it is the behavior that
  silently dropped the panel pass, and a team step is policy.
- Key the matrix on the entry's layer rather than the list's. Rejected at
  kickoff because: the worked example is a per-user entry named by a
  per-project list, and the list is the team's policy of record.

**Chosen because:** a project step is the team's policy of record and a
personal step is one operator's convenience; the blast radius of each
failure matches the layer's, which is the same reasoning the by-layer
malformed policy already records.

### D-7: Three hosting modes, defaulted from dispatch isolation  (N)

**Decision:** `isolated` launches a fresh session through the backend seam
at the step's tier, the preamble prepended to the invocation; `continue`
resumes the immediately preceding step's session in the same list by its
recorded session id; `in-session` runs in the unit's own session, a skill
through its skill tool, a prompt as its next instruction, a command
through its shell tool with the context as assignment prefixes. Unset
hosting maps from `dispatch_isolation`, widening that knob's scope to every
step. A `continue` step on a backend without resume, or whose predecessor
was skipped or left no session id, is a failed step, not a degraded one; a
`continue` step whose predecessor ran as a runner subprocess (a command
step hosted `isolated`) is malformed at resolution, since that is knowable
from the declaration alone; one whose predecessor ran `in-session`
attaches to the unit's session. An `isolated` step on a backend that
cannot spawn keeps the existing dispatch-isolation contract and degrades
to `in-session`, recorded. Model and effort resolve through the existing
per-step allocation knobs keyed on the step id, one-directional as
model-allocation rules.

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

### D-8: Outcomes are runner-classified from the handoff  (N)

**Decision:** Five outcomes: `passed`, `applied`, `halted`, `failed`, and
`skipped` (the matrix's alone). A command step's outcome is its exit code.
A skill or prompt step's outcome is classified by the runner, the session
that receives the step's handoff, from that handoff: `applied` when it
reports a change to the branch, `passed` when none, `halted` for a stop
the step could not resolve, `failed` for an abnormal end or safety stop,
with the excerpt it judged from written into the record. The runner
writes every record, whatever the hosting. Failure posture is per step,
`halt` by default. The classification is a model judgment made
load-bearing, as it already is for the convergence chain today; the
flip-point status extends that trust to the flip evidence, with the
excerpt in the PR body as the review trail.

**Alternatives considered:**
- Require every step to emit a machine-readable result block. Rejected
  because: the operator's existing review commands would each need
  changing before they could be steps, and the doctrine already has the
  host classify the review chain's exits.
- Exit code only, with session steps always passing. Rejected because: a
  review step that found nothing would be indistinguishable from one that
  never ran properly.
- Count only mechanical outcomes toward the flip status. Rejected at
  kickoff because: a review step that halted on a hard-disqualifier is
  exactly what the flip evidence must reflect, and it is a classified
  outcome.

**Chosen because:** it is what `/execute-task` does today for the review
sequence, made explicit, enumerated, and recorded.

### D-9: Mechanics in scripts and one point-of-use rule doc  (N)

**Decision:** Resolution, the missing-step decision, record writing, and
record rendering live in scripts. The vocabulary and contract live in one
rule doc, `doctrine/custom-steps.md`, loaded point-of-use by
`/execute-task`. Each skill carries a one-line call per point, funded by
trimming the review-sequence prose it replaces; `/spec-kickoff` gets only
the script call.

**Alternatives considered:**
- Describe the runner in skill prose. Rejected because: the
  instruction-budget guard's report (`mise run check:instructions`) puts
  both `/execute-task` and `/spec-kickoff` within tens of words of their
  pinned margins, and kickoff's closure likewise.
- Raise the budgets. Rejected because: the headroom ladder puts a raise
  after diet and reclassification, and both are available here.

**Chosen because:** scripts are not instruction surfaces, the existing
declared exceptions require a compensating trim in the same change, and
the convergence section being replaced is the trim.

### D-10: Replace the review-sequence knob outright, warn on the old key  (N)

**Decision:** `review_sequence` is removed from the core defaults, its
resolver deleted, and its every non-spec surface updated. A stale key at
any layer produces one warning naming the layer and the new key, and is
ignored. This repository's own tracked config gains the new key in the
same change and keeps the old line, dated, until the release carrying the
new resolver is installed here, because this repository's units run the
installed plugin, not the checkout; a gated Deferred entry drops it.

**Alternatives considered:**
- Alias then retire (the drafter's recommendation). Rejected because: the
  operator chose a single spelling now over a deprecation window; the
  warning keeps the removal from ever being silent.
- Keep both indefinitely. Rejected because: two spellings and a precedence
  rule between them, forever.
- Hard-fail a repo-tracked stale key. Rejected because: it would block a
  whole team's units on upgrade day for a key that no longer does anything.
- Migrate this repository's config in the same change, accepting the
  window. Rejected at kickoff because: until the upgrade every unit here
  would silently converge through the old resolver's core fallback, the
  exact downgrade the observations recorded, and one warning per run is
  the cheaper cost.

**Chosen because:** operator decision, recorded against the recommendation
so the tradeoff is visible: no adopter path is silently broken, and the
one warning is the migration instruction.

### D-11: The worker guard approves declared command lines  (N)

**Decision:** The allow-only worker command guard learns to approve a
command segment whose word sequence, after the guard's own tokenization
and after stripping leading `PLANWRIGHT_STEP_*` assignments, equals a
declared command step's target followed by its `args` as written, once the
target has passed the guard's charset check and, for a path target, its
canonicalization and traversal rejection. A declared line is one simple
command (no shell operators or expansions), so its word sequence is the
same under the guard, under a shell, and as argv. Declarations are read
only from the human-owned layers and consulted only for a segment not
already known-safe. The trust boundary is the one the profile actually
provides: core and adopter layers sit outside the worktree and the
worker's write set; repo-tracked and machine-local declarations inherit
the trusted-repository-code posture the guard already extends to scripts
under the repository's `scripts/`. This extends
worker-permission-ergonomics' enumerated known-safe set by one
human-declared source, acceptable where extending the ready-guard was not
because the guard stays allow-only.

**Alternatives considered:**
- Operator-maintained allow entries only. Rejected because: a forgotten
  entry stalls an unattended unit until the attention surface notices, the
  same shape as the permission flooding the guard was built to remove.
- Auto-approve any command a step names, without checks. Rejected because:
  the guard's containment and charset checks are what keep an allow-only
  hook from approving a hostile path.
- Match on the first token only (the drafted form). Rejected at kickoff
  because: it approves every invocation of that executable, arguments
  unchecked, when REQ-G1.1 already guarantees the runner executes exactly
  the declared line, so an exact match costs nothing and bounds the allow
  surface to one line per step.
- Match the raw bytes. Rejected because: the guard decides per segment on
  a tokenized word stream with no raw offsets, so bytes are not what it
  compares; word-sequence equality is the same bound at the level the
  decision is made.
- Add path-scoped write denies for the catalogs and config to the worker
  profile. Rejected at kickoff because: a worker can already write and run
  a script under `scripts/`, so the denies would raise the bar for those
  files alone while blocking a worker's own config migration task.
- Approve only declarations from layers outside the worktree. Rejected at
  kickoff because: the repo-tracked layer is where team policy lives, and
  losing auto-approval there re-creates the manual allow entry the guard
  removes.

**Chosen because:** the trust is placed when a human writes the
declaration in a layer that carries the repository's existing trust, and
the guard is deterministic with no model in the decision path.

### D-12: After post-pr, regenerate the checklist and verify the draft; never re-run  (N)

**Decision:** When a post-pr step moves the head, the runner regenerates
the PR body's pending-sign-off checklist from the final range and the
per-point step tables from the records, re-emits the review handoff
through the gate-wiring assembly, and verifies the PR is still a draft,
parking the unit if it is not. Earlier points are not re-run.

**Alternatives considered:**
- Re-run convergence on the new head until a pass moves nothing. Rejected
  because: unbounded cost and its own iteration cap and loop detection,
  when the ready-guard already refuses a flip on a stale or behind-base
  head.
- Do nothing after the step. Rejected because: the stale-checklist gap the
  seeds recorded stays open.
- Regenerate the whole audit record from the range. Rejected at kickoff
  because: gate-wiring makes the audit record judgment-applied from the
  loop-end handoff; only the checklist is a pure function of the range.

**Chosen because:** the checklist is a pure function of the range, the
regeneration is cheap, and the operator's stated wish is fewer re-runs and
re-syncs, not more.

### D-13: A separate spec-PR flip point, plus a unit-kind field  (N)

**Decision:** `pre-spec-ready-flip` is its own list key, run by
`/spec-kickoff`. `pre-ready-flip` governs agent-issued unit-PR flips (the
evidence hook sees the in-session subset of them). Every step's context
carries the unit kind, so a step shared between the two can also branch on
it; "unit" here widens spec-format's task-or-bundle sense to the spec
bundle and the flight, which the glossary should absorb.

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
Environment variables for command steps, added to the inherited host
environment with an absent value set empty; a preamble for session steps,
a block the resolver renders and the runner prepends to the launch prompt
or invocation. No context value is interpolated into a command line.

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
directory. A timed-out session is stopped through the backend seam where
the backend exposes a stop, and otherwise no longer waited on, recorded
either way.

**Alternatives considered:**
- An `env` field. Rejected because: it is where a secret would end up in
  committed config; a step reads credentials from the host environment.
- A `cwd` field. Rejected because: every step runs in the unit's worktree
  and no seed records a need.

**Chosen because:** an external review CLI has returned empty with exit
zero (obs:03653377), which timeout and requires address, and the two
rejected fields add risk without a recorded need.

### D-16: Step records as an in-worktree cache, folded into the PR body  (N)

**Decision:** Records are written per step under
`<worktree>/.claude/steps/`, ignored by this repository's denylist-style
ignore file with its own line (adopters add the same), and rendered as
one table per point inside the PR body's collapsed audit block, with an
empty point still rendering a `none` row. Excerpts are bounded and
screened before they reach the body; the full captured output stays in
the cache. The `status` verb reads the latest attempt's records from the
worktree the flipper ran the point in.

**Alternatives considered:**
- Records under the fleet home. Rejected because: the PR-body assembly runs
  in the worker's checkout, and a unit run outside the fleet has no fleet
  home.
- Records in `tasks.md`. Rejected because: execution state is derived,
  never authored, under format-version 2.

**Chosen because:** the handover brief already establishes the worktree
cache as the home for per-run, non-authoritative state, with an ignore
line per artifact.

### D-17: Reserved controls and the no-recursion rule  (N)

**Decision:** A step never merges, flips ready, force-pushes, or rewrites
history; steps at `pre-implementation`, `pre-ci`, `convergence`, and
`pre-pr` never push; a step may not target a pipeline entry skill, the
literal list living in the rule doc. The worker denies and the ready-guard
apply to steps as to everything else; the no-push ordering is doctrine.

**Alternatives considered:**
- Allow a step to flip ready when issue 379 lands. Rejected because: the
  flip is the act the pre-ready-flip point guards; a step is what runs
  before it, not the thing that performs it.
- Allow a step to dispatch a nested unit. Rejected because: it re-enters the
  pipeline from inside a unit, and the dispatch-entry disjointness rule
  exists to prevent exactly that.

**Chosen because:** the hard invariants are not weighable, and the
no-recursion rule preserves an existing guarantee by a second literal list
whose disjointness test the old enum's own check now targets.

### D-18: Serial only  (N)

**Decision:** Steps at a point run one at a time in list order. Parallel
steps are deferred behind a gate.

**Alternatives considered:**
- Parallel groups within a list. Rejected because: `continue` hosting and
  the pending-sign-off commit discipline both assume a linear history of
  steps, and no seed records a need.

**Chosen because:** determinism was the operator's stated requirement, and
a serial chain is the simplest thing that is deterministic.

### D-19: Foreign plugin namespaces resolve through the installed-plugin registry  (K)

**Decision:** A skill target in planwright's own namespace resolves under
the plugin skills root. One in another plugin's namespace resolves by
mapping the namespace, as the key prefix `<namespace>@`, through Claude
Code's installed-plugin registry to that plugin's install path and probing
its skills and commands directories, generalizing the registry read
`resolve-installed-roots.sh` performs for planwright's own root (the
registry only; that script's cache-directory glob is not carried over). A
namespace matching several registry keys is ambiguous and does not
resolve; a single key listing several install paths is probed in order,
as planwright's own lookup does; an absent or unreadable registry, or no
JSON reader, makes the target non-resolving, never an error. Bare targets
resolve under the plugin skills root and the user and project command and
skill directories as before. A bundled skill with no registry entry does
not resolve.

**Alternatives considered:**
- planwright's namespace only, foreign namespaces unresolvable with a gated
  deferral. Rejected because: planwright is a plugin for adopters, and an
  adopter wanting a marketplace-installed review skill as a step is a
  whole class of users, not a case a seed has to record first.
- Drop the namespace from the grammar. Rejected because: a user skill and a
  planwright skill sharing a name become ambiguous, and other plugins'
  skills become unreachable.

**Chosen because:** the reach matches who the plugin is for, and the
dependency on the registry file's shape is one planwright already carries.

### D-20: A separate evidence hook trusts a commit status the flipper posts  (K)

**Decision:** Whoever flips a PR at a flip point runs the point in a
checkout of the head branch, then posts a commit status on the exact head
the list ended on, in the base repository the PR targets, naming the
point (`success` when no record of that attempt halted or failed, an
empty list included; `failure` otherwise; a later post replaces an
earlier one; a failed post ends the attempt). A separate deny-emitting
hook this bundle owns, wired on the same two flip surfaces as the
ready-guard, reads that head's statuses and refuses an in-session flip of
a PR whose head branch is under `planwright/` unless the `success` status
matching the branch is present, deferring on every other PR and on a fork
head; `ready-guard.sh` and merge-currency-guard's contract stay exactly as
signed, and the raw GraphQL mutation stays the accepted residual it is
there. Planwright's own CI rollup judgements exclude the flip-point
contexts by name. The hook is gated under Deferred until an in-repo
unit-PR flipper that runs the point exists; the status verb and kickoff's
posting land now. The PR-body table remains the human record; the
out-of-session flip is the recovery path when evidence cannot be produced.

**Alternatives considered:**
- Doctrine only until an in-repo flipper lands (the drafted form).
  Rejected because: today's unit flipper is the operator's own session
  issuing the ready command by hand, and REQ-E1.3's SHALL would bind it
  only by memory, the failure obs:4883a86b recorded.
- Extend `ready-guard.sh` with a third read. Rejected because:
  merge-currency-guard REQ-A1.2 has that guard read no check state and
  REQ-C1.1 fixes its predicate at two server signals; a status is check
  state, so the extension amends a signed bundle, where two independent
  deny hooks compose without touching it.
- The guard reads a record from the unit's worktree cache. Rejected
  because: a session flipping from another checkout cannot find that
  worktree, which may also have been pruned, and the ready-guard's
  bounded server-signal posture (merge-currency-guard D-5) is the shape to
  keep.
- The guard parses the pre-ready-flip table out of the PR body. Rejected
  because: prose keyed by a SHA written into it, where a status is keyed to
  the byte-exact head by the server and readable without parsing.
- An empty marker commit carrying a trailer. Rejected because: every
  attempt moves the head the guard then re-checks and adds a commit to
  history.
- Land the hook with the bundle, documenting a hand ritual for unit flips.
  Rejected because: no in-repo flipper of unit PRs runs the point, so
  every task-PR flip would be denied until the operator hand-ran the point
  and the verb, the typed-by-hand step this bundle exists to remove.

**Chosen because:** the flip surfaces are the one chokepoint every
in-session flip passes through, so evidence a hook can read binds every
flipper at once, and a per-SHA status keeps the check server-side and
identical for every flipper. The evidence is written by the same actor the
hook binds (records are an untracked cache the worker can write, and the
verb is a plugin script the worker guard approves), so the hook guards a
flipper that forgets, not one that forges; the stronger property would
need evidence written by CI, which no seed asks for.

## Cross-cutting concerns

- **Instruction budget.** Every skill edit this bundle makes lands with its
  compensating trim in the same change; D-9 is the mechanism. The
  execute-task closure has unpinned headroom for the new rule doc; the
  kickoff closure does not, so kickoff loads no new doc, and its edit to
  `kickoff-verification` is charged to the same closure.
- **Worktree config visibility.** The machine-local layer does not reach
  workers in worktrees; the documentation names the adopter layer as the
  per-user layer that does. Fixing the gap belongs to
  customization-overlay.
- **Data hygiene.** Declarations have no environment field; captured
  output and classification excerpts are screened and bounded before they
  reach the PR body, the unbounded stream staying in the untracked cache.
- **Adopter-visible surface.** The flip-point statuses land in the
  adopter's repository, visible to their own status-consuming tooling; the
  entry format's unknown-field rule means a config written for a newer
  planwright hard-fails an older install in the repo-tracked layer, so a
  team upgrades the plugin before its config.
