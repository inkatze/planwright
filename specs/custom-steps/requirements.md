# Custom steps — Requirements

**Status:** Draft
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

- A named-point vocabulary for the unit's execution process: six points
  wired in this bundle, the orchestrator-side and pipeline-side points named
  now and wired later behind a gate.
- The step declaration: a `steps` catalog kind carrying each step's kind,
  target, arguments, hosting, failure posture, timeout, and required
  executables; one flat config key per point holding the ordered list of
  step ids.
- Resolution through the four overlay layers with printable provenance, the
  resolvability check for every declared step, and the rule for a step that
  does not resolve on the host.
- The execution contract: serial order, the three hosting modes, the fixed
  context a step receives, the outcome vocabulary, per-step failure posture,
  per-step records folded into the PR audit record, and the reserved
  controls a step may never exercise.
- The review points' contracts: convergence (local-only review chain),
  post-pr (steps that iterate against the open PR), pre-ready-flip for unit
  PRs and pre-spec-ready-flip for the spec PR.
- Replacing `review_sequence` with the convergence point's list, migrating
  this repository's own configuration, and updating every non-spec surface
  that named the old key.
- The worker command guard approving declared command targets, the
  resolver and record tooling, the documentation rows, and a `mise run
  check` guard over this repository's own step configuration.

### Out of scope

- Deciding who may flip a task PR from draft to ready (issue 379 keeps
  that decision); merge, unconditionally.
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

## REQ-A — Named attachment points

- **REQ-A1.1** The unit execution process SHALL expose six wired attachment
  points at the moments D-3 defines: `pre-implementation`, `pre-ci`,
  `convergence`, `pre-pr`, and `post-pr`, each fired exactly once per unit
  run, and `pre-ready-flip`, fired once per agent-issued flip attempt on a
  unit PR.
  *(Cites: D-2, D-3, obs:87570535, obs:9eca198f.)*
- **REQ-A1.2** The spec PR's terminal ready-flip SHALL have its own point,
  `pre-spec-ready-flip`, run by `/spec-kickoff` before its terminal flip and
  before the CI gate on the head that flip lands on.
  *(Cites: D-13.)*
- **REQ-A1.3** The vocabulary SHALL name, without wiring them, the points
  `spec-drafted`, `kickoff-signed-off`, `unit-selected`, `pre-dispatch`,
  `post-dispatch`, `unit-halted`, `post-merge`, and `orchestrator-idle`. A
  non-empty list configured for an unwired point SHALL be reported as
  unwired by the resolver, never silently ignored.
  *(Cites: D-2, issue 383 (Sources).)*
- **REQ-A1.4** Every step SHALL receive exactly the fixed context set:
  spec identifier, unit task ids, unit kind (`task`, `spec`, or `flight`),
  branch, base branch, worktree path, PR number (empty when none exists),
  point name, step id, and the path of the preceding step's record (empty
  for the first). It reaches a command step as `PLANWRIGHT_STEP_*`
  environment variables and a skill or prompt step as a preamble; no other
  planwright internal state is passed.
  *(Cites: D-14, D-13.)*
- **REQ-A1.5** The point vocabulary, the moment each point fires, and the
  step contract SHALL have one normative home, a rule doc resolved through
  the rule-doc chain and loaded at point of use by `/execute-task`; skills
  carry the invocation, never the mechanics.
  *(Cites: D-9, REQ-A1.1.)*

## REQ-B — Step declaration

- **REQ-B1.1** A `steps` data catalog SHALL exist at the four overlay
  layers' catalog locations and SHALL be read through the shared catalog
  resolver, merging by append/union with supersede-by-id exactly as the
  existing catalogs do.
  *(Cites: D-4, customization-overlay REQ-B1.3 (Sources).)*
- **REQ-B1.2** A step entry SHALL carry: `id` (the overlay identifier
  charset), `kind` (one of `skill`, `command`, `prompt`), `target`, and
  optionally `args`, `hosting` (one of `isolated`, `continue`,
  `in-session`), `on-failure` (one of `halt`, `continue`; default `halt`),
  `timeout` (a positive integer of seconds; unset means no limit), and
  `requires` (space-separated executable names). An entry with an unknown
  field, an unknown enum value, or a missing required field is malformed
  for its layer under the customization-overlay by-layer policy.
  *(Cites: D-4, D-15, customization-overlay REQ-E1.4 (Sources).)*
- **REQ-B1.3** Each wired point SHALL have one flat config key holding its
  ordered list of step ids, named `steps_<point>` with hyphens written as
  underscores: `steps_pre_implementation`, `steps_pre_ci`,
  `steps_convergence`, `steps_pre_pr`, `steps_post_pr`,
  `steps_pre_ready_flip`, and `steps_pre_spec_ready_flip`. The core default
  for `steps_convergence` is `[polish]` and for every other key the empty
  list, so shipped behavior is unchanged.
  *(Cites: D-4, D-10, customization-boundary (Sources).)*
- **REQ-B1.4** Steps at a point SHALL run serially in list order; a list
  naming the same id twice is malformed; a step at the first position of a
  list declaring `hosting: continue` is malformed, because it has no
  predecessor in that list.
  *(Cites: D-7, D-18.)*
- **REQ-B1.5** Step declarations SHALL carry no secrets or credentials; the
  entry format offers no environment field, and the documentation states
  that a step needing a credential reads it from the host environment.
  *(Cites: D-15, security-posture (Sources).)*
- **REQ-B1.6** A `target` SHALL be validated against its kind's grammar
  before any path or command use: a skill target is a slash-command name
  with an optional plugin namespace; a command target is an executable name
  or path; a prompt target is non-empty text. A failing target is never
  interpolated.
  *(Cites: D-4, security-posture (Sources).)*

## REQ-C — Resolution

- **REQ-C1.1** Point lists SHALL resolve through the config reader with
  last-layer-wins per key, and the resolver SHALL print one warning naming
  every lower layer whose list for that point was shadowed by the winning
  layer.
  *(Cites: D-5.)*
- **REQ-C1.2** The resolver SHALL print, on request, provenance per step:
  the point, the step id, the layer that supplied the winning list, the
  layer that supplied the step entry, the resolved target, and the hosting.
  *(Cites: D-5, customization-overlay REQ-B1.6 (Sources).)*
- **REQ-C1.3** Before any step at a point runs, every id in the point's
  list SHALL resolve to a catalog entry and every entry's target SHALL
  resolve on the host: a skill target under the plugin skills root or the
  Claude Code user and project command and skill directories, a command
  target as an executable on the path or at the given path, a prompt target
  as non-empty text; every `requires` executable SHALL be found on the
  path. The `--nested` frontmatter test that gated the old knob is not
  applied; nestedness is an argument the operator passes.
  *(Cites: D-4, obs:680c2761, obs:b1414bbd, issue 393 (Sources).)*
- **REQ-C1.4** A step that does not resolve on the host SHALL be handled by
  the layer that supplied the winning list and by attendance: in an
  attended session the runner surfaces the missing step and waits, at every
  layer; in an unattended run a step declared by the repo-tracked layer
  parks the unit to Awaiting input before any step at that point runs,
  while a step declared by the adopter or machine-local layer is skipped
  with a warning and a skip record in the unit's audit record. A step from
  the core default list that does not resolve is a broken install and parks
  the unit at every attendance.
  *(Cites: D-6, obs:9eca198f.)*
- **REQ-C1.5** A structurally malformed list value or catalog entry SHALL
  follow the customization-overlay by-layer policy: hard-fail for the
  repo-tracked layer, warn and degrade to the core default for the adopter
  and machine-local layers, each naming the layer.
  *(Cites: D-5, customization-overlay REQ-E1.4 (Sources).)*
- **REQ-C1.6** A `review_sequence` key present at any layer SHALL produce
  one warning naming the layer, the removed key, and `steps_convergence`;
  its value SHALL be ignored.
  *(Cites: D-10.)*
- **REQ-C1.7** A resolved step's model and effort SHALL come from the
  existing per-step allocation knobs keyed on the step id, which already
  accept any identifier in the step charset; no new allocation key is
  introduced.
  *(Cites: D-7, model-allocation D-8 (Sources).)*
- **REQ-C1.8** The resolver SHALL refuse a step whose target is a pipeline
  entry skill (`execute-task`, `orchestrate`, `drain`, `spec-draft`,
  `spec-kickoff`, `offload`, `tower`), so a step never re-enters the
  pipeline and the dispatch-entry command set stays disjoint from step
  targets by construction.
  *(Cites: D-17, fleet-autonomy REQ-E1.2 (Sources).)*

## REQ-D — Execution contract

- **REQ-D1.1** The runner SHALL execute a point's steps in order and end
  each with an outcome from exactly the set `passed`, `applied`, `halted`,
  `failed`. A command step maps exit zero to `passed` and any other exit,
  or a timeout, to `failed`. A skill or prompt step's outcome is classified
  by the hosting session from the step's handoff, and the record carries
  the excerpt the classification rests on.
  *(Cites: D-8.)*
- **REQ-D1.2** A `halted` or `failed` step whose posture is `halt` SHALL
  end the point and the unit per the gate-wiring pause protocol: an
  unattended run parks the unit to Awaiting input naming the point, the
  step, and the outcome; an attended session presents it and waits. A
  posture of `continue` records the outcome and proceeds to the next step.
  *(Cites: D-8, gate-wiring (Sources).)*
- **REQ-D1.3** Hosting SHALL mean: `isolated`, a fresh session seeded from
  durable state and the context preamble, launched through the backend seam
  at the step's resolved tier; `continue`, the session the immediately
  preceding step in the same list ran in, reached by that session's
  recorded id; `in-session`, the session running the unit. A step with no
  hosting takes `isolated` under `dispatch_isolation: per-step` and
  `in-session` under `per-unit`. A command step under `isolated` runs as a
  runner subprocess with its output captured to the record; under the other
  two modes the named session executes it.
  *(Cites: D-7, bootstrap D-5 (Sources).)*
- **REQ-D1.4** A step declaring `continue` on a backend that cannot resume
  the predecessor's session SHALL not run and SHALL take outcome `failed`
  naming the backend and the hosting, so its posture applies.
  *(Cites: D-7.)*
- **REQ-D1.5** Every step SHALL leave a record carrying the point, step id,
  kind, target, hosting, backend, session id where one exists, start and
  end times, outcome, the classification excerpt, and a skip reason when
  skipped. Records live as an in-worktree cache, never as tracked state, and
  the per-point record tables fold into the PR body's collapsed audit block;
  the turn reports counts.
  *(Cites: D-16, gate-wiring (Sources).)*
- **REQ-D1.6** A step SHALL NOT merge, mark a PR ready, force-push, amend,
  squash, or rebase, and a step at any point before `post-pr` SHALL NOT
  push. The worker permission denies and the ready-guard stay in force for
  every step.
  *(Cites: D-17, bootstrap REQ-J1.4 (Sources), merge-currency-guard REQ-A1.3
  (Sources).)*
- **REQ-D1.7** A step exceeding its `timeout` SHALL be ended by the runner
  where it owns the process, or no longer waited on where a session owns
  it, with outcome `failed` and the timeout named in the record.
  *(Cites: D-15, obs:00dccd4e.)*
- **REQ-D1.8** A `requires` executable missing on the host SHALL be handled
  as a step that does not resolve, under REQ-C1.4.
  *(Cites: D-15, D-6.)*
- **REQ-D1.9** Resolution SHALL complete for a whole point before its first
  step runs; a point either runs its resolved list or runs nothing.
  *(Cites: D-6.)*

## REQ-E — The review points

- **REQ-E1.1** At `convergence` the runner SHALL sync `main` once before
  the first step, per merge-currency-guard, and each step's audit record
  SHALL fold into the PR body as the review chain's does today; the three
  existing dispositions map onto the outcome set: a normal exit is `passed`
  or `applied`, a safety stop is `failed`, and an unresolved
  hard-disqualifier finding is `halted`.
  *(Cites: D-3, D-8, merge-currency-guard REQ-B1.1 (Sources).)*
- **REQ-E1.2** `post-pr` SHALL fire after the draft PR is open and its body
  assembled; a step there MAY push to the unit branch. After the list
  completes, if the head moved, the runner SHALL regenerate the PR body's
  audit record and pending-sign-off checklist from the final range, and
  SHALL verify the PR is still a draft, parking the unit to Awaiting input
  naming the step when it is not.
  *(Cites: D-12, obs:ff5ca260, obs:02396e39.)*
- **REQ-E1.3** Any agent-issued draft-to-ready flip of a unit PR SHALL run
  `steps_pre_ready_flip` on the head to be flipped first and SHALL refuse
  the flip on a `halted` or `failed` step. The ready-guard's currency check
  stays orthogonal, and this bundle authorizes no flip.
  *(Cites: D-13, obs:4883a86b, merge-currency-guard REQ-A1.4 (Sources).)*
- **REQ-E1.4** The dispatch brief SHALL cite the point keys and never
  restate a resolved list.
  *(Cites: obs:508c1d85.)*

## REQ-F — Replacement of the review-sequence knob

- **REQ-F1.1** `review_sequence` SHALL be removed from the core defaults,
  its resolver deleted, and `/execute-task`'s convergence phase SHALL read
  `steps_convergence`.
  *(Cites: D-10.)*
- **REQ-F1.2** This repository's repo-tracked configuration SHALL be
  migrated to `steps_convergence` in the same change that removes the key.
  *(Cites: D-10.)*
- **REQ-F1.3** Every non-spec surface naming `review_sequence` (scripts,
  tests, documentation, doctrine worked examples, and skill prose) SHALL be
  updated in the same change, and a grep over those surfaces afterwards
  returns only the migration-warning site. Signed spec bundles are history
  and are not edited.
  *(Cites: D-10.)*
- **REQ-F1.4** The per-step allocation knobs for `polish` and `self-review`
  SHALL keep their names and semantics, documented as step-id-keyed.
  *(Cites: D-7, model-allocation D-8 (Sources).)*
- **REQ-F1.5** Any skill that converges a flight SHALL read
  `steps_convergence` with unit kind `flight`; tower-front-door's reference
  to the one configured review sequence resolves to the convergence
  point's list, and its bundle is not edited.
  *(Cites: D-10, D-13, tower-front-door REQ-C1.3 (Sources).)*

## REQ-G — Security and permissions

- **REQ-G1.1** Context values SHALL reach a command step only through its
  environment; a declared command line is executed as the operator wrote
  it, and no context value is ever interpolated into it.
  *(Cites: D-14, security-posture (Sources).)*
- **REQ-G1.2** Step catalogs and point lists SHALL be read only from the
  human-owned overlay layers; the worker permission profile SHALL NOT allow
  writes to them, so a dispatched worker cannot add steps to its own run.
  *(Cites: D-11, fleet-autonomy REQ-F1.3 (Sources).)*
- **REQ-G1.3** The worker command guard SHALL auto-approve a command whose
  first token equals a declared command step's resolved target, after the
  charset and containment checks it applies to plugin scripts, as an
  allow-only decision; the documentation keeps the manual allow entry as
  the fallback for the guard's degraded path.
  *(Cites: D-11, worker-permission-ergonomics (Sources).)*
- **REQ-G1.4** A skill step SHALL run under the worker's permission profile
  like any other skill, with no elevation.
  *(Cites: D-11.)*

## REQ-H — Documentation, tooling, and guards

- **REQ-H1.1** Every new config key SHALL have a row in the options
  reference, and the options check SHALL pass.
  *(Cites: bootstrap REQ-K1.8 (Sources).)*
- **REQ-H1.2** The overlay documentation SHALL describe the `steps` catalog
  and replace the review-sequence worked example with a steps example that
  shows a per-user catalog entry used by a per-project list.
  *(Cites: D-4, D-10.)*
- **REQ-H1.3** A resolver command SHALL print a point's resolved chain, with
  provenance on request, and a check mode that exits non-zero on any
  unresolvable step; a record helper SHALL write, list, and render step
  records.
  *(Cites: D-9, D-16.)*
- **REQ-H1.4** `mise run check` SHALL gain a guard that resolves every wired
  point against this repository's own configuration in check mode, and the
  instruction-budget guard SHALL pass on the skill edits this bundle makes.
  *(Cites: D-9, instruction-headroom D-11 (Sources).)*
- **REQ-H1.5** The new rule doc SHALL be registered in the doctrine index
  and in the manifest of every skill that loads it.
  *(Cites: D-9.)*

## Changelog

- 2026-09-22 — Draft. Elicited from the review-gauntlet seed brief, issues
  383 and 393, and the observation fragments cited in Sources;
  fold-detection scanned every bundle and spun a new sibling, with
  customization-overlay, bootstrap, and merge-currency-guard cited as
  Sources rather than reopened.

## Sources

- **The review-gauntlet seed** — `specs/_pending/review-gauntlet.md`, scoped
  out of fleet-autonomy on 2026-07-14: the operator's gauntlet, the
  nestability gap, and the open questions on chaining and granularity.
- **Issue 383** — "Name the pipeline's lifecycle states and let operators
  attach hooks (commands or skills) to them", the general-mechanism request
  and its candidate point list. Pinned altitude claim: "the general
  mechanism is missing", "narrow by construction".
- **Issue 393** — "review_sequence cannot reach the review skills that live
  outside the plugin", the three candidate directions.
- **Issue 379** — the ready-flip policy proposal; cited as the boundary this
  bundle provides a point for and does not decide.
- **obs:87570535** — the 2026-09-02 operator request for named states with
  attachable hooks and the design questions a spec must settle.
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
- **obs:02396e39** — a reviewer request silently un-drafted a PR.
- **obs:fbb56815** — the convergence loop runs CI once, then the review
  sequence once, linearly.
- **obs:36916a48** — the operator's unit-sizing and sync-frugality wish,
  recorded during this drafting session and routed out of scope.
- **Worktree config gap** — obs:fd4c2ad6, obs:65fea955, obs:4467db6b, left
  unconsumed: the machine-local layer is invisible from worktrees.
- **customization-overlay** — `specs/customization-overlay/`, the overlay
  layers, the catalog merge contract (REQ-B1.3), provenance (REQ-B1.6), and
  the by-layer malformed policy (REQ-E1.4).
- **customization-boundary** — `doctrine/customization-boundary.md`, the
  capability-versus-style rule and its review-sequence worked example.
- **bootstrap** — `specs/bootstrap/`, owner of `/execute-task`: step
  isolation (D-5), the never-rewrite rule (REQ-J1.4), the options reference
  (REQ-K1.8).
- **merge-currency-guard** — `specs/merge-currency-guard/`, the ready-guard
  and the flipper-agnostic rule (REQ-A1.3, REQ-A1.4), the convergence sync
  (REQ-B1.1).
- **model-allocation** — `specs/model-allocation/`, the open step-type key
  space (D-8).
- **fleet-autonomy** — `specs/fleet-autonomy/`, the dispatch-entry
  disjointness rule (REQ-E1.2) and the human-owned-layer posture (REQ-F1.3).
- **worker-permission-ergonomics** — `specs/worker-permission-ergonomics/`,
  the allow-only worker command guard.
- **tower-front-door** — `specs/tower-front-door/`, flights converging
  through the configured review sequence (REQ-C1.3) and the seam-reuse rule
  (REQ-G1.5).
- **instruction-headroom** — `specs/instruction-headroom/`, the declared
  exceptions pinning `/execute-task` and `/spec-kickoff` near their floors.
- **gate-wiring** — `doctrine/gate-wiring.md`, the pause protocol and
  PR-body assembly.
- **security-posture** — `doctrine/security-posture.md`, framework-script
  security and artifact data hygiene.
- **The fold-detection scan** — every bundle under `specs/` on 2026-09-21;
  overlap with the three cited bundles, spin-new triggers fired on the new
  external interface and the orthogonal decisions.
