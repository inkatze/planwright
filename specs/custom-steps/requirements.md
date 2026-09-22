# Custom steps — Requirements

**Status:** Ready
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's execution process has one pipeline-semantic extension point,
the `review_sequence` knob, and it admits only planwright's own skills whose
frontmatter declares `--nested`. The verification chain the operator actually
runs on every unit is half outside that set: the panel and Copilot review
passes ship as user commands, so on every dispatched unit they are typed in
by hand or skipped, the ready-flip has fired before they ran, and a bare
nested polish pass run as a tower step left the sign-off checklist stale
(obs:87570535, obs:9eca198f, obs:4883a86b, obs:ff5ca260). Nothing lets an
operator say "at this point in the unit's process, run this" for any other
point either, and the one existing knob degrades a whole list when a single
entry is not a plugin skill (obs:b1414bbd, obs:680c2761).

This bundle gives the unit's execution process **named attachment points**
and lets an operator declare, per point and through the existing overlay
layers, an ordered list of **steps** to run there. A step is a skill or user
command with arguments, a shell command, or a free-text prompt; it declares
where it is hosted (a fresh session, the previous step's session, or the
worker's own), what happens when it fails, and optionally a timeout and the
executables it needs. Step definitions live in a catalog that merges across
layers; each point's ordered list is one flat config key, so the chain that
runs is exactly the chain declared, resolvable and printable with provenance
before anything runs. `review_sequence` is replaced by the convergence
point's list. Points that need an open PR exist, so the Copilot loop becomes
a declared step rather than a manual one, and a point before any
agent-issued ready-flip exists so the flip can follow the whole gauntlet,
without this bundle deciding who flips. The deliverable's altitude,
capability plus doctrine with the mechanics in scripts and the operator's
own gauntlet staying in an overlay, is recorded in D-1 and cited here from
the goal.
*(Cites: D-1, D-2, the review-gauntlet seed (Sources), issue 383 (Sources),
issue 393 (Sources), obs:87570535, obs:9eca198f, obs:4883a86b,
obs:ff5ca260, obs:b1414bbd, obs:680c2761.)*

## Scope

### In scope

- A named-point vocabulary for the unit's execution process: the in-run
  points and the spec-PR flip point wired in this bundle, the unit-PR flip
  point defined here and wired by the first in-repo flipper, the
  orchestrator-side and pipeline-side points named now and wired later
  behind a gate.
- The step declaration: a `steps` catalog kind carrying each step's kind,
  target, arguments, hosting, failure posture, timeout, and required
  executables; one flat config key per point holding the ordered list of
  step ids.
- Resolution through the overlay layers with printable provenance, the
  resolvability check for every declared step, and the rule for a step that
  does not resolve on the host.
- The execution contract: serial order, the three hosting modes, the fixed
  context a step receives, the outcome vocabulary, per-step failure posture,
  per-step records folded into the PR body, and the reserved controls a
  step may never exercise.
- The review points' contracts: convergence (local-only review chain),
  post-pr (steps that iterate against the open PR), pre-ready-flip for unit
  PRs and pre-spec-ready-flip for the spec PR.
- Replacing `review_sequence` with the convergence point's list, migrating
  this repository's own configuration, and updating every non-spec surface
  that named the old key.
- The worker command guard approving declared command lines, the
  resolver and record tooling, the documentation rows, and a `mise run
  check` guard over this repository's own step configuration.
- The flip-point evidence: a commit status the flipper posts on the head
  after the flip point runs, and a separate evidence hook of this bundle's
  own that denies an in-session flip lacking it (the hook gated under
  Deferred until an in-repo unit-PR flipper exists to produce the
  evidence).

### Out of scope

- Deciding who may flip a task PR from draft to ready (issue 379 keeps
  that decision; this bundle adds one precondition to the spec-PR flip
  now, and to every in-session flip once the evidence hook is un-gated,
  and authorizes none); merge, unconditionally.
- Shipping planwright-owned wrappers for external review tools. The panel
  and Copilot commands stay where they live and are named from an overlay.
- Fixing machine-local configuration not reaching worktrees
  (obs:fd4c2ad6, obs:65fea955, obs:4467db6b); this bundle cites the
  constraint and documents the adopter layer as the per-user layer that
  reaches workers.
- Wiring the orchestrator-side and pipeline-side points; they are named
  here and gated under Deferred.
- Per-spec or per-task-type step lists; parallel steps within one point;
  both gated under Deferred.
- Re-running earlier points when a later step moves the branch head. The
  ready-guard's currency check and merge-currency-guard's sync rule cover
  the head; obs:36916a48 records the operator's wider wish about unit
  sizing and sync frugality for a bundle that owns those rules.
- Editing the operator's own review commands, or any step's internal loop
  and convergence criteria.
- Steps editing signed spec content outside the amendment ritual the
  meta-spec defines.
- Flip surfaces the ready-guard does not cover (merge-currency-guard
  REQ-C1.10's accepted residual, the raw GraphQL mutation); the evidence
  hook inherits exactly the ready-guard's two surfaces.
- Evidence written by CI rather than by the flipper; the flip-point status
  guards a flipper that forgets, not one that forges (D-20).

## REQ-A — Named attachment points

- **REQ-A1.1** The unit execution process SHALL expose the in-run
  attachment points at the moments D-3 defines: `pre-implementation`,
  `pre-ci`, `convergence`, `pre-pr`, and `post-pr`, each fired exactly once
  per unit run; and SHALL define `pre-ready-flip`, fired once per
  agent-issued flip attempt on a unit PR by whichever in-repo flipper
  issues it, none existing yet (REQ-E1.3).
  *(Cites: D-2, D-3, obs:87570535, obs:9eca198f.)*
- **REQ-A1.2** The spec PR's terminal ready-flip SHALL have its own point,
  `pre-spec-ready-flip`, run by `/spec-kickoff` after its push and PR step
  and before the terminal CI gate on the head that flip lands on, fired
  once per kickoff sign-off that reaches the push and PR step, whether or
  not the flip is configured to follow.
  *(Cites: D-13, D-3.)*
- **REQ-A1.3** The vocabulary SHALL name, without wiring them, the points
  `spec-drafted`, `kickoff-signed-off`, `unit-selected`, `pre-dispatch`,
  `post-dispatch`, `unit-halted`, `post-merge`, and `orchestrator-idle`
  (issue 383's `tower-idle` under the glossary tower-front-door REQ-H1.1
  supersedes). A non-empty list configured for an unwired point SHALL be
  reported as unwired by the resolver and by the `check:steps` guard, never
  silently ignored. The point vocabulary is core-owned: an adopter needing
  a moment planwright does not name records an observation, the growth
  path the other catalogs use, because every point is a moment inside a
  skill only core can wire.
  *(Cites: D-2, issue 383 (Sources), tower-front-door REQ-H1.1 (Sources).)*
- **REQ-A1.4** Every step SHALL receive exactly the fixed context set:
  spec identifier, unit task ids (empty for a spec-kind unit), unit kind
  (`task`, `spec`, or `flight`), branch, base branch, worktree path, PR
  number (empty when none exists, so on a re-execution against an open PR
  it is set at every point), point name, step id, and the path of the
  preceding step's record (empty for the first). It reaches a command step
  as the `PLANWRIGHT_STEP_*` environment variables the rule doc names,
  added to the inherited host environment, an absent value set to the empty
  string, never unset; it reaches a skill or prompt step as a preamble, a
  rendered block the resolver prints and the runner prepends to the step's
  launch prompt or invocation. The runner neither scrubs the inherited
  environment nor adds any other planwright internal state.
  *(Cites: D-14, D-13, obs:00dccd4e.)*
- **REQ-A1.5** The point vocabulary, the moment each point fires, and the
  step contract SHALL have one normative home, a rule doc resolved through
  the rule-doc chain and loaded point-of-use by `/execute-task`; skills
  carry the invocation, never the mechanics.
  *(Cites: D-9, REQ-A1.1.)*

## REQ-B — Step declaration

- **REQ-B1.1** A `steps` data catalog SHALL exist at the four overlay
  layers' catalog locations and SHALL be read through the shared catalog
  resolver, merging by append/union with supersede-by-id exactly as the
  existing catalogs do; the catalog reader's `supersede` marker is part of
  the entry format and never an unknown field.
  *(Cites: D-4, customization-overlay REQ-B1.3 (Sources).)*
- **REQ-B1.2** A step entry SHALL carry: `id` (the skill-name charset
  `^[a-z][a-z0-9-]*$`, at most 64 bytes, validated before any key or path
  use; `implementation` is reserved for the unit's own implementation
  phase and never a step id), `kind` (one of `skill`, `command`,
  `prompt`), `target`, and optionally `args`, `hosting` (one of
  `isolated`, `continue`, `in-session`), `on-failure` (one of `halt`,
  `continue`; default `halt`), `timeout` (a positive integer of seconds;
  unset means no limit), and `requires` (space-separated executable
  names). Every value is a single-line scalar of the constrained catalog
  reader. An entry with an unknown field, an unknown enum value, an id
  outside the charset, or a missing required field is malformed for its
  layer under REQ-C1.5. So is an entry whose fields cannot be honored
  together: `timeout` on a skill or prompt step hosted `in-session` (the
  unit session cannot end itself) and `args` on a `prompt` step (the target
  is the whole prompt).
  *(Cites: D-4, D-15, customization-overlay REQ-E1.2 (Sources),
  customization-overlay REQ-E1.4 (Sources).)*
- **REQ-B1.3** Every named point SHALL have one flat config key holding its
  ordered list of step ids, named `steps_<point>` with hyphens written as
  underscores (`steps_pre_implementation`, `steps_pre_ci`,
  `steps_convergence`, `steps_pre_pr`, `steps_post_pr`,
  `steps_pre_ready_flip`, `steps_pre_spec_ready_flip`, and one per unwired
  point). The value is an inline flow list of step ids; `[]` resolves to
  no steps and is not malformed. The core default for `steps_convergence`
  is `[polish]` and for every other key the empty list, so shipped behavior
  is unchanged.
  *(Cites: D-4, D-10, customization-boundary (Sources).)*
- **REQ-B1.4** Steps at a point SHALL run serially in list order; a list
  naming the same id twice is malformed; a step declaring `hosting:
  continue` is malformed at the first position of a list, because it has no
  predecessor there, and immediately after a command step hosted
  `isolated`, because a runner subprocess records no session to attach to.
  *(Cites: D-7, D-18.)*
- **REQ-B1.5** Step declarations SHALL carry no secrets or credentials; the
  entry format offers no environment field, and the overlay documentation
  states that a step needing a credential reads it from the host
  environment the runner inherits (REQ-A1.4).
  *(Cites: D-15, security-posture (Sources).)*
- **REQ-B1.6** A `target` SHALL be validated against its kind's grammar
  before any path or command use: a skill target is `<name>` or
  `<plugin>:<name>` (the slash-command name without its leading slash, the
  namespace being Claude Code's invocation form); a command target is an
  executable name or path; a prompt target is non-empty single-line text.
  A command step's `args` is a sequence of plain words: no shell
  operators, redirections, expansions, or quoting, so the declared line is
  one simple command whose word sequence is the same under a shell and as
  argv. A skill step's `args` is passed to the invocation verbatim and
  never shell-interpreted. A failing target or args is malformed for its
  layer under REQ-C1.5 and is never interpolated.
  *(Cites: D-4, D-11, security-posture (Sources).)*

## REQ-C — Resolution

- **REQ-C1.1** Point lists SHALL resolve through the config reader with
  last-layer-wins per key, and the resolver SHALL print one warning naming
  every lower layer whose list for that point was shadowed by the winning
  layer, read through the config reader's per-layer mode (Task 2 adds it;
  the reader's merged mode exposes only the winner).
  *(Cites: D-5.)*
- **REQ-C1.2** The resolver SHALL print, on request, provenance per step:
  the point, the step id, the layer that supplied the winning list, the
  layer that supplied the step entry, the resolved target, and the hosting.
  The entry layer is provenance only and never changes a decision.
  *(Cites: D-5, customization-overlay REQ-B1.6 (Sources).)*
- **REQ-C1.3** Before any step at a point runs, every id in the point's
  list SHALL resolve to a catalog entry and every entry's target SHALL
  resolve on the host: a bare skill target under the plugin skills root or
  the Claude Code user and project command and skill directories; a skill
  target in planwright's own namespace under the plugin skills root; a
  skill target in another plugin's namespace under that plugin's install
  path (its skills and commands directories), located through Claude
  Code's installed-plugin registry by the namespace as the key prefix
  `<plugin>@`, the registry being the only source; a namespace matching
  several registry keys, an absent or unreadable registry, or a missing
  JSON reader makes the target non-resolving under REQ-C1.4, never an
  error (a single key whose value lists several install paths is probed in
  order, as planwright's own root lookup does); a command target as an
  executable on the path or at the given path; a prompt target as
  non-empty text; every `requires` executable SHALL be found on the path.
  An id naming no catalog entry is handled as a step that does not
  resolve. The `--nested` frontmatter test that gated the old knob is not
  applied; nestedness is an argument the operator passes.
  *(Cites: D-4, D-19, obs:680c2761, obs:b1414bbd, issue 393 (Sources).)*
- **REQ-C1.4** A step that does not resolve on the host SHALL be handled by
  the layer that supplied the winning list and by attendance, the resolver
  printing one decision token per step: `run` for a resolved step; in an
  attended session `ask` (the runner surfaces the missing step and waits)
  for a missing step from any overlay layer; in an unattended run `park`
  for a step declared by the repo-tracked layer (the unit parks to Awaiting
  input before any step at that point runs) and `skip` for a step declared
  by the adopter or machine-local layer (a warning and a skip record in the
  unit's step records); a step from the core default list that does not
  resolve is a broken install and prints `park` at both attendances.
  Attendance is passed explicitly by the hosting skill (`--unattended`
  exactly when the unit was launched headless, per the backend seam's
  launch record; `--attended` otherwise); the resolver has no default.
  *(Cites: D-6, obs:9eca198f.)*
- **REQ-C1.5** A malformed list value or catalog entry, structural or
  semantic (REQ-B1.2, REQ-B1.4, REQ-B1.6, REQ-C1.8), SHALL follow the
  by-layer policy: a malformed core value or entry is a broken install
  (exit 5); a malformed repo-tracked value or entry hard-fails (exit 4); a
  malformed adopter or machine-local list value warns and degrades to the
  core default, as the list resolvers already do because the merged reader
  exposes only the winner (a deliberate divergence from
  customization-overlay REQ-E1.4's next-lower-layer rule, recorded in this
  repository's tracked config); a malformed adopter or machine-local
  catalog entry warns and is skipped, as the catalog reader already does,
  its id then non-resolving under REQ-C1.4; each naming the layer.
  *(Cites: D-5, customization-overlay REQ-E1.4 (Sources).)*
- **REQ-C1.6** A `review_sequence` key present at any layer SHALL produce
  one warning per layer naming the layer, the removed key, and
  `steps_convergence`, read through the per-layer mode; its value SHALL be
  ignored.
  *(Cites: D-10.)*
- **REQ-C1.7** A resolved step's model and effort SHALL come from the
  existing per-step allocation knobs keyed on the step id with hyphens
  written as underscores (the same spelling rule as REQ-B1.3; the id
  charset in REQ-B1.2 is the knobs' own), under model-allocation's
  one-directional rule: a configured step tier applies only where it is
  strictly cheaper than the unit's tier and the surface carries a tier,
  and is otherwise ignored with a ledger row; an `in-session` step inherits
  the session's tier, recorded and not applied. No new allocation key is
  introduced.
  *(Cites: D-7, model-allocation D-8 (Sources), model-allocation REQ-E1.1
  (Sources).)*
- **REQ-C1.8** The resolver SHALL refuse, as malformed for its layer, a
  step whose target is a pipeline entry skill: the dispatch-entry command
  enum planwright ships (`execute-task`, `orchestrate`, `drain`) plus the
  skills that open or advance the pipeline (`spec-draft`, `spec-kickoff`,
  `offload`, and `tower`, forward-declared for tower-front-door), a literal
  list the rule doc owns and the resolver reads from it, so a step never
  re-enters the pipeline; the dispatch-entry enum's own disjointness test
  keeps its scope and is retargeted from the retired nestable predicate to
  this refusal.
  *(Cites: D-17, fleet-autonomy REQ-E1.2 (Sources).)*

## REQ-D — Execution contract

- **REQ-D1.1** The runner (the session hosting the unit, or the flipper at
  a flip point, with the scripts it calls) SHALL execute a point's steps in
  order and end each with an outcome from exactly the set `passed`,
  `applied`, `halted`, `failed`, `skipped`. A command step maps exit zero
  to `passed` and any other exit, or a timeout, to `failed`. A skill or
  prompt step's outcome is classified by the runner from the handoff the
  step's session returns: `applied` when the handoff reports a change to
  the branch (a commit, an applied finding), `passed` when it reports none,
  `halted` when it reports a stop the step could not resolve, `failed` when
  the session ended abnormally or reported a safety stop; the record
  carries the excerpt the classification rests on. `skipped` is produced
  only by the missing-step matrix (REQ-C1.4). The runner writes every
  record, whatever the hosting.
  *(Cites: D-8, obs:03653377.)*
- **REQ-D1.2** A `halted` or `failed` step whose posture is `halt` SHALL
  end the point: at an in-run point it ends the unit through the
  gate-wiring pause protocol's two destinations (an unattended run parks
  the unit to Awaiting input naming the point, the step, and the outcome;
  an attended session presents it and waits), and at a flip point it
  refuses the flip and surfaces the step. A posture of `continue` records
  the outcome and proceeds to the next step.
  *(Cites: D-8, gate-wiring (Sources).)*
- **REQ-D1.3** Hosting SHALL mean: `isolated`, a fresh session launched
  through the backend seam (`offload-dispatch`) at the step's resolved
  tier, with the preamble prepended to the skill invocation or prompt text
  that is its launch prompt; `continue`, the session the immediately
  preceding step in the same list ran in, resumed by its recorded session
  id with the same invocation; `in-session`, the session running the unit,
  which invokes a skill step through its skill tool with the declared
  `args` and a prompt step as its next instruction. A step with no hosting
  takes `isolated` under `dispatch_isolation: per-step` and `in-session`
  under `per-unit`; this widens that knob's documented scope from the
  implementation and review steps to every step at every point. A command
  step under `isolated` runs as a runner subprocess with its output
  captured to the cache; under the other two modes the named session
  executes it through its shell tool as the declared line prefixed by the
  `PLANWRIGHT_STEP_*` assignments. A `continue` step whose predecessor ran
  `in-session` attaches to the unit's session, which is `in-session` by
  another name. An `isolated` step on a backend that cannot spawn a fresh
  session degrades to `in-session` and records the degradation, keeping
  the existing dispatch-isolation contract.
  *(Cites: D-7, orchestration-fleet D-5 (Sources).)*
- **REQ-D1.4** A step declaring `continue` on a backend that cannot resume
  the predecessor's session, or whose predecessor was skipped or recorded
  no session id (a predecessor hosted `in-session` excepted, per
  REQ-D1.3), SHALL not run and SHALL take outcome `failed` naming the
  backend, the hosting, and the missing predecessor, so its posture
  applies.
  *(Cites: D-7.)*
- **REQ-D1.5** Every step SHALL leave a record carrying the head SHA at
  its start, the run id (one per unit run or flip attempt), the point,
  step id, kind, target, hosting, backend, session id where one exists,
  start and end times, outcome, a bounded excerpt (the classification
  excerpt for a session step, the tail of the captured output for a
  command step, screened for secret shapes and non-printable bytes and
  rendered table-safe), the path of the full captured output in the cache
  where one exists, and a skip reason when skipped; the runner also writes
  one point-completion record per point it runs, empty list included,
  carrying the point, run id, head SHA, and the resolver's warnings. Records
  live under `<worktree>/.claude/steps/`, an untracked cache (this
  repository's ignore list names it; adopters add the same line, and the
  documentation says so), never as tracked state. The per-point record
  tables fold into the PR body's collapsed audit block, a point that ran
  nothing still emitting its table with a single `none` row and its
  warnings; the turn reports counts.
  *(Cites: D-16, gate-wiring (Sources), security-posture (Sources).)*
- **REQ-D1.6** A step SHALL NOT merge, mark a PR ready, force-push, amend,
  squash, or rebase, and a step at `pre-implementation`, `pre-ci`,
  `convergence`, or `pre-pr` SHALL NOT push; a step at `post-pr` or either
  flip point MAY. The worker permission denies and the ready-guard keep
  enforcing the rewrite and flip controls for every step; the no-push
  ordering is doctrine, enforced by no mechanism.
  *(Cites: D-17, bootstrap REQ-J1.4 (Sources), merge-currency-guard REQ-A1.3
  (Sources).)*
- **REQ-D1.7** A step exceeding its `timeout` SHALL be ended by the runner
  where it owns the process; where an `isolated` or `continue` session
  owns it, the runner stops the session through the backend seam when the
  backend exposes a stop and otherwise stops waiting on it, recording which
  applied; in both cases the outcome is `failed` with the timeout named in
  the record. A stopped-waiting session that later pushes moves the head
  outside the record, which the ready-guard's currency check and the
  post-pr draft verification cover. An `in-session` skill or prompt step
  carries no timeout (REQ-B1.2); an `in-session` command step's timeout is
  passed to the session's shell tool.
  *(Cites: D-15, obs:03653377.)*
- **REQ-D1.8** A `requires` executable missing on the host SHALL be handled
  as a step that does not resolve, under REQ-C1.4.
  *(Cites: D-15, D-6.)*
- **REQ-D1.9** Resolution SHALL complete for a whole point before its first
  step runs; a point either runs its resolved list or runs nothing.
  *(Cites: D-6.)*

## REQ-E — The review points

- **REQ-E1.1** At `convergence` the runner SHALL resolve the point, then
  sync `main` once per merge-currency-guard whenever the point fires (an
  empty list included), then run the steps; each review step's handoff
  folds into the PR body as the review chain's does today; the existing
  dispositions map onto the outcome set: a normal exit is `passed` or
  `applied`, a normal exit carrying a queued meaning-class spec fork is
  `halted` (the rule that stops PR creation today survives the trim), a
  safety stop is `failed`, and an unresolved hard-disqualifier finding is
  `halted`.
  *(Cites: D-3, D-8, obs:c97cda97, obs:fbb56815, merge-currency-guard
  REQ-B1.1 (Sources).)*
- **REQ-E1.2** `post-pr` SHALL fire after the draft PR is open and its body
  assembled; a step there MAY push to the unit branch. After the list
  completes, if the head moved, the runner SHALL regenerate the PR body's
  pending-sign-off checklist from the final range and the per-point step
  tables from the records, re-emit the review handoff through the
  gate-wiring assembly, and SHALL verify the PR is still a draft, parking
  the unit to Awaiting input naming the step when it is not.
  *(Cites: D-12, obs:ff5ca260, obs:02396e39.)*
- **REQ-E1.3** Any agent-issued draft-to-ready flip of a unit PR SHALL run
  `steps_pre_ready_flip` on the head to be flipped first and SHALL refuse
  the flip on a `halted` or `failed` step. At either flip point, a step
  that pushes moves the head, and the flip targets the head the list ends
  on; the flip's own gates (the ready-guard's currency check for a unit PR,
  the CI gate for the spec PR) then check that head. The ready-guard's
  currency check stays orthogonal; this bundle authorizes no flip.
  *(Cites: D-3, D-13, obs:4883a86b, merge-currency-guard REQ-A1.4
  (Sources).)*
- **REQ-E1.4** `/orchestrate`'s dispatch prose, and the prompt it produces,
  SHALL cite the point keys and never restate a resolved list.
  *(Cites: obs:508c1d85.)*
- **REQ-E1.5** The flipper SHALL leave server-side evidence of the flip
  point's outcome: after the point's list completes (an empty list
  included), it posts a commit status on the exact head the list ended on,
  in the base repository the PR targets, context
  `planwright/pre-ready-flip` for a unit PR and
  `planwright/pre-spec-ready-flip` for the spec PR, state `success` when no
  record of the latest attempt for that head is `halted` or `failed`
  (`skipped` and the classified outcomes count as the record says) and
  `failure` otherwise; a later post on the same head and context replaces
  the earlier one; a post that fails, a missing status-write permission
  included, ends the flip attempt without a flip, surfaced like a failed
  step, the documentation naming the permission the flipper's login needs.
  Those contexts SHALL be excluded, by context name, from every CI rollup
  judgement planwright makes, so a flip point's own status never counts as
  a completed check; adopters' own status-consuming tooling sees them, and
  the documentation says so. A separate evidence hook of this bundle's
  own, on the two flip surfaces the ready-guard covers (the shell ready
  command and the GitHub MCP update tool), SHALL refuse an in-session
  draft-to-ready flip of a PR whose head branch is under `planwright/`
  unless the head carries the `success` status matching the branch (the
  spec-branch form requires the spec context, every other `planwright/`
  head the unit context), SHALL deny on a status read that errors, and
  SHALL defer on every other PR and on a PR whose head repository differs
  from its base; the out-of-session flip is the recovery path. That hook
  lands only once an in-repo unit-PR flipper exists to run the point
  (gated under Deferred), and it binds a flipper that forgets, not one that
  forges. The PR-body table stays the human record; the status is what the
  hook trusts.
  *(Cites: D-20, D-16, obs:4883a86b, merge-currency-guard D-5,
  merge-currency-guard REQ-A1.2, merge-currency-guard REQ-C1.1,
  merge-currency-guard REQ-C1.10 (Sources).)*

## REQ-F — Replacement of the review-sequence knob

- **REQ-F1.1** `review_sequence` SHALL be removed from the core defaults,
  its resolver deleted, and `/execute-task`'s convergence phase SHALL read
  `steps_convergence`; the `check:steps` guard SHALL fail on the old key in
  the core defaults or in this repository's configuration outside the
  documented transitional line.
  *(Cites: D-10.)*
- **REQ-F1.2** This repository's repo-tracked configuration SHALL gain
  `steps_convergence` in the same change that removes the key from core,
  keeping `review_sequence` beside it with a dated comment until the
  release carrying the new resolver is installed here (the installed plugin
  is what this repository's own units run), then dropping the old line
  under a gated Deferred entry.
  *(Cites: D-10.)*
- **REQ-F1.3** Every non-spec surface naming the old knob, by key or by
  prose (`review_sequence`, `review-sequence`, `review sequence`, and the
  retired resolver's script name) SHALL be updated by the task that owns
  the surface (the skill bodies by Tasks 5 and 6, everything else by
  Task 3), and afterwards a repository-tracked grep over `scripts/`,
  `tests/`, `docs/`, `doctrine/`, `skills/`, `config/`, and the tracked
  files under `.claude/` returns only the stale-key warning site, the
  fixtures that exercise it, and the transitional line REQ-F1.2 keeps.
  Signed spec bundles are history and are not edited.
  *(Cites: D-10.)*
- **REQ-F1.4** The per-step allocation knobs for `polish` and `self-review`
  SHALL keep their names; their key's referent becomes the step id, and the
  options rows say so.
  *(Cites: D-7, model-allocation D-8 (Sources).)*
- **REQ-F1.5** Any skill that converges a flight SHALL read
  `steps_convergence` with unit kind `flight`; tower-front-door's
  references to the one configured review sequence resolve to the
  convergence point's list, and its bundle is not edited.
  *(Cites: D-10, D-13, tower-front-door REQ-C1.3 (Sources),
  tower-front-door REQ-G1.5 (Sources).)*

## REQ-G — Security and permissions

- **REQ-G1.1** Context values SHALL reach a command step only through its
  environment; a declared command line is executed as the operator wrote
  it, as argv by the runner subprocess and as the same simple command by a
  session, never through shell interpretation of anything beyond word
  splitting, and no context value is ever interpolated into it.
  *(Cites: D-14, REQ-B1.6, security-posture (Sources).)*
- **REQ-G1.2** Step catalogs and point lists SHALL be read only from the
  human-owned overlay layers. The core and adopter layers sit outside the
  worktree and outside a dispatched worker's write set; the repo-tracked
  and machine-local layers sit inside it and inherit the existing
  trusted-repository-code posture, the same trust the guard already
  places in a script under the repository's `scripts/`. The worker
  permission profile is unchanged by this bundle.
  *(Cites: D-11, fleet-autonomy (Sources), worker-permission-ergonomics
  (Sources).)*
- **REQ-G1.3** The worker command guard SHALL auto-approve a command
  segment whose word sequence, after the guard's own tokenization and
  after stripping leading `PLANWRIGHT_STEP_*` assignments, equals a
  declared command step's target followed by its `args` as written, once
  the target has passed the guard's charset check and, for a path target,
  its canonicalization and traversal rejection, as an allow-only decision;
  a segment sharing only the first word is not approved. This extends
  worker-permission-ergonomics REQ-A1.5's enumerated known-safe set by one
  human-declared source, acceptable where extending the ready-guard was not
  because the guard stays allow-only and the trust is placed by the
  declaration's layer (REQ-G1.2). The declared steps are consulted only
  for a segment not already known-safe, within the guard's existing
  wall-clock bound. The documentation keeps the manual allow entry as the
  fallback for the guard's degraded path.
  *(Cites: D-11, REQ-G1.1, worker-permission-ergonomics REQ-A1.5
  (Sources).)*
- **REQ-G1.4** A skill step SHALL run under the worker's permission profile
  like any other skill, with no elevation.
  *(Cites: D-11.)*

## REQ-H — Documentation, tooling, and guards

- **REQ-H1.1** Every new config key SHALL have a row in the options
  reference, and the options check SHALL pass.
  *(Cites: bootstrap REQ-K1.8 (Sources).)*
- **REQ-H1.2** The overlay documentation SHALL describe the `steps`
  catalog (correcting its enumeration of the growable catalogs), the
  `PLANWRIGHT_STEP_*` context set, the record cache and its ignore line,
  the credential rule of REQ-B1.5, the status-write permission of
  REQ-E1.5, and the note that a repo-tracked step naming an external tool
  is a team-wide disclosure decision whose declaration is the consent
  record; and SHALL replace the review-sequence worked example with a
  steps example that shows a per-user catalog entry used by a per-project
  list.
  *(Cites: D-4, D-10, D-14.)*
- **REQ-H1.3** A resolver command SHALL print a point's resolved chain
  (one `<decision>\t<id>` line per step, in order; `--explain` appending
  the REQ-C1.2 provenance fields tab-separated; `--preamble` printing the
  REQ-A1.4 block) and exit 0 when every step is `run`, 1 when the point
  runs nothing (`park` or `ask`), 4 on a repo-tracked malformation, 5 on a
  broken install; a check mode (`--check`) SHALL exit non-zero on any
  `park`, on any malformation, and on any `skip` from a core or
  repo-tracked list, and pass with a warning on a `skip` from the adopter
  or machine-local layer; a record helper SHALL write, list, and render
  step records and regenerate the pending-sign-off checklist.
  *(Cites: D-9, D-16.)*
- **REQ-H1.4** `mise run check` SHALL gain a guard that resolves every
  named point against this repository's own configuration in check mode
  (unwired keys included, per REQ-A1.3), and the instruction-budget guard
  SHALL pass on the skill edits this bundle makes.
  *(Cites: D-9, instruction-headroom D-11 (Sources).)*
- **REQ-H1.5** The new rule doc SHALL be registered in the doctrine index
  and in the manifest of every skill that loads it, the manifest resolution
  verified by the instruction-budget guard's manifest pass.
  *(Cites: D-9.)*

## Changelog

- 2026-09-22 — Draft. Elicited from the review-gauntlet seed brief, issues
  383 and 393, and the observation fragments cited in Sources;
  fold-detection scanned every bundle and spun a new sibling, with the
  three fold-detection candidates (customization-overlay, bootstrap, and
  merge-currency-guard) cited as Sources rather than reopened.
- 2026-09-22 — Kickoff walkthrough edits (Draft, unsigned): REQ-B1.2 and
  REQ-B1.4 refuse three un-honorable declarations at resolution; REQ-C1.3
  resolves foreign plugin namespaces through the installed-plugin registry
  (D-19); REQ-E1.3 gains the moved-head rule; REQ-E1.5 and D-20 add the
  flip-point commit status (Task 9) and a separate evidence hook, gated
  under Deferred, that leaves merge-currency-guard's guard as signed;
  REQ-G1.3 matches the declared line's word sequence; REQ-B1.6 and
  REQ-G1.1 pin a declared line to one simple command; REQ-D1.3's isolation
  citation retargeted from bootstrap to orchestration-fleet D-5.
- 2026-09-22 — Sign-off lens pass edits (Draft, unsigned): the resolver's
  output and exit contract (REQ-H1.3), decision tokens and explicit
  attendance (REQ-C1.4), the by-layer policy split for lists and entries
  (REQ-C1.5), the step-id charset and the reserved phase id (REQ-B1.2),
  records gaining head, run id, bounded excerpt, and a pinned untracked
  path (REQ-D1.5), a `skipped` outcome and the runner as classifier
  (REQ-D1.1), context delivery to session-hosted command steps (REQ-D1.3,
  REQ-G1.3), REQ-G1.2 restated to the trust the worker profile actually
  provides, REQ-F1.2's transitional migration through the upgrade window,
  the `pre-ready-flip` point defined rather than wired (REQ-A1.1), and the
  citation repairs (fleet-autonomy, model-allocation, obs:03653377,
  obs:c97cda97, obs:fbb56815, issue 383's pinned quote).

## Sources

- **The review-gauntlet seed** — `specs/_pending/review-gauntlet.md`, scoped
  out of fleet-autonomy on 2026-07-14: the operator's gauntlet, the
  nestability gap, and the open questions on chaining and granularity.
- **Issue 383** — "Name the pipeline's lifecycle states and let operators
  attach hooks (commands or skills) to them", the general-mechanism request
  and its candidate point list (its `tower-idle` is this bundle's
  `orchestrator-idle`). Pinned altitude claim: "narrow by construction";
  the companion claim "the general mechanism is missing" is obs:87570535's.
- **Issue 393** — "review_sequence cannot reach the review skills that live
  outside the plugin", the three candidate directions.
- **Issue 379** — the ready-flip policy proposal; cited as the boundary this
  bundle provides a point for and does not decide.
- **obs:87570535** — the 2026-09-02 operator request for named states with
  attachable hooks and the design questions a spec must settle; pinned
  altitude claim "the general mechanism is missing".
- **obs:680c2761** — the nestable predicate admits only plugin skills.
- **obs:b1414bbd** — an external name degrades the whole list to the default.
- **obs:9eca198f** — overnight-run PRs reached green with zero review passes.
- **obs:ff5ca260** — bare nested polish leaves the sign-off checklist stale.
- **obs:4883a86b** — the ready-flip fired before the panel and Copilot passes.
- **obs:508c1d85** — a dispatch brief restated the review sequence by hand.
- **obs:c97cda97** — execute-task's fixed review-before-PR order and the
  hard-disqualifier deliverable case.
- **obs:00dccd4e** — a shell-variable profile signal unreadable inside a
  worker; context must reach steps by a channel the worker can read.
- **obs:03653377** — an external review CLI returning an empty response
  with exit zero; the case timeout and requires exist for, and the reason a
  command step's exit code alone is `passed`.
- **obs:02396e39** — a reviewer request silently un-drafted a PR.
- **obs:fbb56815** — the convergence loop runs CI once, then the review
  sequence once, linearly.
- **obs:36916a48** — the operator's unit-sizing and sync-frugality wish,
  recorded during this drafting session and routed out of scope.
- **Worktree config gap** — obs:fd4c2ad6, obs:65fea955, obs:4467db6b, left
  unconsumed: the machine-local layer is invisible from worktrees.
- **customization-overlay** — `specs/customization-overlay/`, the overlay
  layers, the catalog merge contract (REQ-B1.3), provenance (REQ-B1.6),
  identifier validation before interpolation (REQ-E1.2), and the by-layer
  malformed policy (REQ-E1.4).
- **customization-boundary** — `doctrine/customization-boundary.md`, the
  capability-versus-style rule and its review-sequence worked example.
- **bootstrap** — `specs/bootstrap/`, owner of `/execute-task`: the
  never-rewrite rule (REQ-J1.4), the options reference (REQ-K1.8).
- **orchestration-fleet** — `specs/orchestration-fleet/`, the
  `dispatch_isolation` knob and per-step session hosting (D-5), whose text
  names the review-sequence gauntlet this bundle replaces.
- **merge-currency-guard** — `specs/merge-currency-guard/`, the ready-guard
  and the flipper-agnostic rule (REQ-A1.3, REQ-A1.4), the convergence sync
  (REQ-B1.1), the guard's no-check-state and two-signal contract (REQ-A1.2,
  REQ-C1.1), its accepted residual surface (REQ-C1.10), and its
  server-signal decision (D-5), left as signed by the separate evidence
  hook.
- **model-allocation** — `specs/model-allocation/`, the one-directional
  step-tier rule (D-8) and the open, injective step-id knob space (REQ-E1.1
  and the options rows).
- **fleet-autonomy** — `specs/fleet-autonomy/`, the dispatch-entry
  disjointness rule (REQ-E1.2) and its kickoff brief's note that the
  worker's trust boundary is the permission allowlist, not the config
  reader.
- **worker-permission-ergonomics** — `specs/worker-permission-ergonomics/`,
  the allow-only worker command guard and its enumerated known-safe set
  (REQ-A1.5).
- **tower-front-door** — `specs/tower-front-door/`, flights converging
  through the configured review sequence (REQ-C1.3, REQ-G1.5) and the
  glossary supersession (REQ-H1.1).
- **instruction-headroom** — `specs/instruction-headroom/`, the declared
  exceptions pinning `/execute-task` and `/spec-kickoff` near their floors.
- **gate-wiring** — `doctrine/gate-wiring.md`, the pause protocol and
  PR-body assembly.
- **security-posture** — `doctrine/security-posture.md`, framework-script
  security and artifact data hygiene.
- **The fold-detection scan** — every bundle under `specs/` on 2026-09-21;
  overlap with the three fold-detection candidates, spin-new triggers fired
  on the new external interface and the orthogonal decisions.
