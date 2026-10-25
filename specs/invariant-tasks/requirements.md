# Invariant Tasks — Requirements

**Status:** Ready
**Last reviewed:** 2026-10-25
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

`tasks.md` today mixes two kinds of content: invariant task *definitions*
(deliverables, done-when, dependencies) and volatile *state* (which section a
block sits in, `Status` / `Last activity` / `Dispatch` annotations, the bundle
`Status:` header). The state half is already a derived read-model snapshot
(orchestration-concurrency D-1): the derivation engine, not the committed
file, is the truth — yet every state change still means editing a committed
file: section moves, annotation stamps, reconcile commits, anchor churn, and
(on shared checkouts) index races that forced one deployment to disable
state-move commits outright. The gate orchestration-concurrency set on this
graduation — the fleet spec surfacing a concrete need to drop the committed
snapshot — is met on its own terms: fleet-scale operation (the two-tower
shared-checkout deployment) hit the snapshot as a write-race liability, and
the fleet meta-tower already bypasses it, reading the live derivation, not
the committed file.

This bundle graduates to the sanctioned Maximal variant that
orchestration-concurrency deliberately deferred: the committed `tasks.md`
holds only invariant task definitions (plus the human-payload sections that
cannot be derived); all execution status is derived from git/PR ground truth
and rendered on demand, never committed. Fewer writes, no state drift by
construction, and the anchor/hook machinery that existed to tolerate state
churn simplifies or retires. The deliverable's altitude is recorded in D-1
(a format-capability graduation, landing as format-version 2 of the
meta-spec), per the altitude trigger the drafting invocation fired.

**Extension (2026-10-25): tasks in more than one repository.** A bundle
whose tasks change code in several repositories cannot be executed today:
a task block names no repository, so the derivation reads every task's
state from the one work repository the resolver picks, a dependency merged
in another repository reads as unmet, and every unit dispatches into the
launch repository. Splitting such a bundle per repository loses exactly
the cross-repository dependency edges. The extension lets a task name,
by alias, the repository its code lives in, and has the derivation read
each task's state, and so each dependency's, from the repository that task
names (REQ-F). The field changes the task block grammar, so it lands as
format-version 3 of the meta-spec (D-13); the alias resolves to a local
checkout through `custom-spec-location`'s work-repository registry, never
through anything stored in the bundle (D-14). The altitude is unchanged:
a format capability under D-1, with the mechanism confined to the scripts
that implement the format.
*(Cites: D-13, D-14, D-15; mission-control D-22 (Sources); obs:74a7f907.)*

## Scope

### In scope

- The Maximal graduation of `tasks.md`: the committed file holds invariant
  task definition blocks and the human-payload sections (Awaiting input,
  Deferred, Out of scope); no committed placement sections, no committed
  state annotations.
- Bundle `Status:` header: Active and Done become derived, rendered on
  demand; Draft→Ready stays a stored human-gated flip; Retired and
  Superseded stay stored human declarations.
- Format-version 2 of `doctrine/spec-format.md`, with v1 bundles still valid
  under their declared version.
- The status-aware validator: v2 rules, continued v1 support.
- The on-demand status render: the existing derivation engine surfaced as
  the human-readable view that replaces reading committed sections.
- Reconciling the machinery that existed to tolerate state churn: the
  level-triggered reconcile writer's `tasks.md` role, the `tasks-pr-sync`
  hook, the `check-ledger` guard, output-hygiene's normative completion
  annotation (supersede ritual where contracts change), and the content
  anchor's churn profile.
- Migration of this repo's live (Draft/Ready/Active) bundles to v2; Done
  and terminal bundles stay v1 untouched.
- *(Extension 2026-10-25.)* Format-version 3: an optional per-task
  `Repository:` definition field naming the task's repository by alias;
  the validator, the canonical extraction, and every version-keyed script
  taught the new version; the derivation, selection, gate evaluation, and
  render reading each task's state from the repository it names.

### Out of scope

- Re-deciding orchestration-concurrency's derivation internals or evidence
  precedence — consumed, not redefined.
- Selection policy (which ready unit is chosen) — unchanged.
- Dispatch backends, observe/steer, attention surfaces —
  orchestration-fleet's seams.
- Moving the human-payload sections (Awaiting input, Deferred, Out of scope)
  out of the committed file — deliberately not taken (their content is
  human-authored and not derivable from git evidence).
- The kickoff brief / sign-off machinery beyond what the anchor churn
  profile change requires.
- Rewriting Done or terminal bundles to v2 — the meta-spec's coexistence
  model exists so finished records never need rewriting.
- Auto-merge at any tier — permanent carried invariant.
- Non-GitHub git hosts.
- *(Extension 2026-10-25.)* The alias-to-checkout map itself: owned by
  `custom-spec-location`'s work-repository registry, consumed here.
- *(Extension 2026-10-25.)* Dispatching a unit into its task's repository
  from a holder checkout: `custom-spec-location`'s holder dispatch, which
  reads the field this bundle defines.
- *(Extension 2026-10-25.)* A task spanning several repositories in one
  block, and a task that touches no repository (a tracker edit): the first
  splits into tasks joined by dependency edges, the second stays outside
  execution (`custom-spec-location` excludes execution without a git work
  repository).
- *(Extension 2026-10-25.)* Migrating existing bundles to version 3: a
  bundle declares it only when a task needs the field.

## REQ-A — The invariant committed ledger (format-version 2)

- **REQ-A1.1** Under format-version 2, `tasks.md` SHALL contain task
  definition blocks and human-payload sections only (Awaiting input,
  Deferred, Out of scope); it SHALL NOT carry committed placement sections
  (Forward plan / In progress / Completed) or state annotation bullets
  (Status / Last activity / Dispatch).
  *(Cites: D-2, D-3.)*
- **REQ-A1.2** A committed edit to a task block SHALL occur only for
  definition changes (via the amendment ritual); derived execution-state
  changes SHALL NOT produce commits to the bundle. Committed writes to the
  human-payload sections (parking and unparking under D-3, whether written
  by the human or a halting skill) are human-owned payload, not execution
  state.
  *(Cites: D-2, D-3; orchestration-concurrency D-1 (Sources).)*
- **REQ-A1.3** The stored `Status:` header SHALL be restricted to
  human-gated states (Draft, Ready, Retired, Superseded); Active and Done
  SHALL be derived from evidence and rendered on demand, never stored.
  *(Cites: D-4, D-5.)*
- **REQ-A1.4** Format-version 2 SHALL preserve unchanged the stable
  never-reused IDs, the five task definition fields, and the
  dependency-edge contract; only the state layer moves out of the committed
  file.
  *(Cites: D-2.)*

## REQ-B — Derived status as the read surface

- **REQ-B1.1** An on-demand render SHALL present per-task execution status
  and the bundle's effective status (Active/Done), derived via
  orchestration-concurrency's evidence chain (PR/merge state, commit/branch
  reachability, the commit trailer, the runtime dispatch marker), never
  committed.
  *(Cites: D-6; orchestration-concurrency REQ-C1.1 (Sources).)*
- **REQ-B1.2** The render SHALL work with no remote configured, degrading
  per the existing evidence-fallback rules; the solo/prototyping flow stays
  first-class. (A configured-but-failing remote is not this mode; that
  case is carved out to REQ-B1.5.)
  *(Cites: D-6.)*
- **REQ-B1.3** For v2 bundles the render SHALL be the canonical
  execution-status read surface; skills and docs SHALL reference it rather
  than committed sections, and no derived-status artifact is committed or
  pushed to a remote mirror.
  *(Cites: D-6.)*
- **REQ-B1.4** A committed reference bullet SHALL be authoritative for its
  task's state in the derivation: human-owned parked state (an
  Awaiting-input, Deferred, or Out-of-scope bullet naming the task id,
  authored by the human or a halting skill per D-3) outranks git-evidence
  inference for that task. Bullet authority applies
  to bullets on the derivation's read surface (the primary checkout's main
  view); a bullet committed only on an unmerged task branch takes effect
  when it lands, the task deriving in-progress from its branch evidence
  until then (documented limitation; risk register).
  *(Cites: D-3; kickoff sign-off (2026-07-14).)*
- **REQ-B1.5** The derivation SHALL distinguish a transient evidence-fetch
  failure (remote configured but unreachable, rate-limited, or erroring)
  from the no-remote mode, and SHALL fail closed on it: the render reports
  the failure rather than presenting partial evidence as status, unit
  selection dispatches nothing, and gate task-completion atoms resolve as
  unresolved. The derivation engine SHALL signal the failure distinctly (a
  documented signal its consumers branch on); a definitive negative result
  (no PR exists for a branch) is evidence, not failure. Locally-determinable
  facts (the stored header, reference-bullet parked state) do not depend on
  the remote and are still reported during a transient failure, marked as
  the only facts available.
  *(Cites: D-6, D-8; kickoff sign-off (2026-07-14).)*
- **REQ-B1.6** Derived bundle status SHALL be computed only for bundles
  whose stored header reads Ready; Draft, Retired, and Superseded bundles
  render their stored state with no execution claim. A bundle with zero
  task blocks SHALL never derive Done (the render reports it has no
  tasks), and a live Awaiting-input bullet SHALL block derived Done at the
  bundle level. Tasks parked by a Deferred or Out-of-scope bullet are
  excluded from the Done universe rather than blocking it (open Deferred
  gates do not block Done).
  *(Cites: D-4; kickoff sign-off (2026-07-14).)*

## REQ-C — Machinery reconciliation

- **REQ-C1.1** The `tasks.md` state-sync writer and its hook SHALL be
  version-keyed: v1 bundles keep today's reconcile behavior; on v2 bundles
  the writer performs no placement, annotation, or derived-header writes.
  *(Cites: D-7.)*
- **REQ-C1.2** Unit selection SHALL derive candidacy for v2 bundles without
  committed placement: dependencies-met and not-completed/in-progress via
  the derivation engine; parked-ness via the committed human-payload
  sections.
  *(Cites: D-8.)*
- **REQ-C1.3** Gate evaluation SHALL resolve task completion through the
  derivation engine rather than `## Completed` section membership.
  *(Cites: D-8.)*
- **REQ-C1.4** The ledger guard SHALL retain structural checks (canonical
  heading form, duplicate task IDs) for v2 bundles; placement-vs-annotation
  coherence checks SHALL apply to v1 bundles only.
  *(Cites: D-7.)*
- **REQ-C1.5** The validator SHALL enforce the v2 invariants — no
  placement sections, no state annotations, stored header restricted to
  the human-gated set, the static `Execution:` pointer line present (in
  its fixed vocabulary), and reference-bullet integrity (every bullet
  names an existing task id; at most one bullet per task across all
  human-payload sections — a task is parked in one section at a time) — as
  errors on the signed-off live statuses (Ready, Active, Done), warnings on
  Draft, and warnings on the Retired and Superseded terminal records, per the
  carried bootstrap D-25 severity model; v1 rules stay for v1 bundles.
  *(Cites: D-7, D-5, D-3.)*
- **REQ-C1.6** No orchestration or execution act on a v2 bundle SHALL
  change its content anchor: state changes touch no committed spec file, so
  anchor churn from state movement is impossible by construction.
  *(Cites: D-9.)*
- **REQ-C1.7** The normative completion annotation SHALL be superseded for
  v2 bundles: completion is derived render content, and the supersession
  against output-hygiene's contract is recorded via the supersede ritual.
  *(Cites: D-11.)*
- **REQ-C1.8** A bundle whose `Format-version:` line is missing or
  unparseable SHALL be handled fail-closed by every version-keyed script:
  no writes are performed and the validator reports an error; no script
  falls open to the v1 write path.
  *(Cites: D-7; kickoff sign-off (2026-07-14).)*
- **REQ-C1.9** The framework-script security rules SHALL be bound in the
  touched machinery: the migration validates identifiers, containment-checks
  paths, and refuses hostile input with a clean, sanitized error; the
  render, the migration's output, and the new v2 validator/guard error
  paths sanitize all echoed untrusted content (`sanitize_printable`) —
  spec-file values, reference-bullet text, branch names, and evidence- or
  remote-derived text alike; reference-bullet task ids are validated
  against the task-id grammar before any use; the v2 format definition
  carries the artifact data-hygiene note for bullet free text.
  *(Cites: D-3, D-10; kickoff sign-off (2026-07-14).)*

## REQ-D — Migration & coexistence

- **REQ-D1.1** A bundle's declared `Format-version:` SHALL select which
  rules and machinery apply; v1 bundles remain valid and operable
  indefinitely.
  *(Cites: D-7.)*
- **REQ-D1.2** A migration path SHALL convert a live v1 bundle to v2
  (collapse placement sections into the single task list, strip state
  annotations, convert parked task blocks in any human-payload section to
  reference bullets, restrict the header, add the pointer line), preserving
  task definition lines byte-for-byte so the `tasks.md` canonical
  extraction is unchanged; the required re-anchor rides the migration as
  expression-only. The migration SHALL be idempotent (an already-v2 bundle
  is a clean no-op), per-bundle atomic, and re-runnable after a partial
  run; the per-bundle unit includes a signed bundle's re-anchor entry
  together with the dated Changelog line it cites (appended to the
  bundle's `requirements.md`, per the meta-spec's execution-validity rule
  for expression-only entries), and a re-run SHALL complete a missing
  re-anchor rather than no-op past it.
  *(Cites: D-10; kickoff sign-off (2026-07-14).)*
- **REQ-D1.3** planwright's own live (Draft/Ready/Active) bundles SHALL be
  migrated to v2; Done and terminal bundles SHALL stay v1 untouched. A
  Draft bundle takes the same byte-stable transform; having no signed
  brief, it takes no re-anchor entry.
  *(Cites: D-10; kickoff §2 (2026-07-14).)*

## REQ-E — Doctrine, skills, config, and lineage

- **REQ-E1.1** `doctrine/spec-format.md` SHALL define format-version 2 via
  the meta-spec's own versioning ritual: the v2 `tasks.md` shape, the
  restricted stored-status vocabulary with the static pointer line, and
  derivation as the read surface.
  *(Cites: D-1, D-2, D-5.)*
- **REQ-E1.2** Every skill that writes or reads the committed state layer
  SHALL be reconciled for v2, keyed off the bundle's declared
  `Format-version:` exactly as the scripts are (D-7) — v1 bundles keep
  today's skill behavior: `/spec-draft` authors v2 bundles;
  `/execute-task` drops the `Last activity` write on v2 bundles; `/resume`
  and every
  human-facing status summary read the render, while `/orchestrate`'s
  selection and `/drain`'s gate evaluation read the derivation engine via
  their scripts (D-6, D-8); `/orchestrate`'s dead-worker orphan reconcile
  parks via an Awaiting-input bullet (a halting-skill payload write per
  REQ-A1.2) written on the derivation's read surface — the primary
  checkout's main view (REQ-B1.4), never the dead worker's branch;
  `/spec-kickoff`'s delta/amendment mode selection reads derived
  status (the stored header rests at Ready); Awaiting-input writes stay
  committed.
  *(Cites: D-6, D-7, D-8, D-3; kickoff sign-off (2026-07-14).)*
- **REQ-E1.3** Config knobs made vacuous for v2 (`commit_on_state_move`)
  SHALL be documented as v1-only in the options reference.
  *(Cites: D-7.)*
- **REQ-E1.4** orchestration-concurrency's Deferred "Maximal variant" gate
  entry SHALL be closed with an annotation citing this bundle as the
  graduation it was gating on.
  *(Cites: orchestration-concurrency Deferred gate (Sources).)*

## REQ-F — Per-task repositories (format-version 3)

- **REQ-F1.1** Format-version 3 SHALL be format-version 2 plus one
  optional task definition field, `Repository:`, naming the repository
  whose branches, pull requests, and commit trailers carry that task's
  execution state. A task block without the field SHALL belong to the
  bundle's work repository, resolved exactly as today. Version 1 and 2
  bundles SHALL stay valid unchanged, and a `Repository:` field in a bundle
  that does not declare version 3 SHALL be invalid.
  *(Cites: D-13; mission-control REQ-H1.2 (Sources); obs:74a7f907.)*
- **REQ-F1.2** The field's value SHALL be a single alias matching the
  identifier grammar, never a path, URL, or host name; a block SHALL carry
  at most one `Repository:` field and the field SHALL name exactly one
  repository. The alias SHALL resolve to a local checkout only through the
  machine-local work-repository registry `custom-spec-location` defines;
  nothing in the bundle SHALL name a checkout.
  *(Cites: D-14.)*
- **REQ-F1.3** The canonical `tasks.md` extraction SHALL keep a version 3
  block's `Repository:` field line and its continuations as definition
  content, so adding, removing, or changing a task's repository changes the
  content anchor. For a bundle in which no block carries the field, the
  extraction SHALL be byte-identical to the version 2 extraction.
  *(Cites: D-13.)*
- **REQ-F1.4** The derivation engine SHALL derive each task's execution
  state from the repository that task's field names, or from the bundle's
  work repository when the field is absent, and dependency satisfaction
  SHALL read each dependency's state from the repository that dependency
  names. Unit selection, gate evaluation, and the status render SHALL all
  consume this per-task derivation; the render SHALL show the alias of
  every task that names one.
  *(Cites: D-15; mission-control REQ-H1.2 (Sources).)*
- **REQ-F1.5** A task whose alias does not resolve on the machine running
  the derivation (no registry entry, a stale entry, a checkout that is
  gone) SHALL derive a distinct `unresolved` state naming the alias: it is
  never selected, a dependency on it is unmet, a gate atom on it resolves
  unresolved, and the bundle never derives Done while any task is
  unresolved. Tasks whose repositories resolve SHALL derive normally.
  *(Cites: D-15.)*
- **REQ-F1.6** REQ-B1.5's transient-failure rule SHALL hold per
  repository: a failed evidence fetch in any repository the bundle's tasks
  resolve to SHALL be reported naming that repository's alias, unit
  selection for the bundle SHALL dispatch nothing, and gate atoms on that
  repository's tasks SHALL resolve unresolved.
  *(Cites: D-15, D-8.)*
- **REQ-F1.7** The validator SHALL enforce the version 3 field rules (the
  field's grammar, at most one per block, the alias grammar, the field
  present only under a version 3 declaration) at the REQ-C1.5 severities,
  with echoed values sanitized (REQ-C1.9); every version-keyed script SHALL
  give version 3 its version 2 behavior plus the field, and an undefined
  version SHALL stay fail-closed (REQ-C1.8).
  *(Cites: D-13, D-7.)*
- **REQ-F1.8** `doctrine/spec-format.md` SHALL define format-version 3
  through its versioning ritual, and `/spec-draft` SHALL declare version 3
  only for a bundle in which some task names a repository, offering the
  field when the elicitation surfaces a second repository.
  *(Cites: D-13, D-14.)*

## Open questions for the kickoff

The extension was drafted by an unattended worker with no operator
present. Each choice below is the option `mission-control` most directly
implies; the kickoff confirms or reverses it.

1. **Version bump rather than an additive v2 field (D-13).** Version 2
   says a block carries its five fields "and nothing else", and an older
   install would silently drop an unknown bullet from the extraction and
   dispatch into the launch repository; a bump makes that install refuse
   the bundle instead. The alternative is an additive v2 field.
2. **An alias, resolved by `custom-spec-location`'s registry (D-14).** The
   alternatives, a checkout path or a remote URL, put machine layout or a
   host name in a committed file.
3. **One repository per task (D-14, REQ-F1.2).** A multi-repository unit
   form was considered and not taken; multi-repository work splits into
   tasks joined by edges, which now cross repositories.
4. **Bundle-wide fail-closed on a transient failure in any one repository
   (REQ-F1.6).** A per-repository scope would keep selecting in healthy
   repositories at the cost of a second failure mode to reason about.
5. **Cross-bundle ordering.** Task 11 resolves aliases through the registry
   `custom-spec-location`'s extension delivers (that bundle's Task 11).
   The dependency grammar has no cross-bundle edge, so the ordering is
   carried in Task 11's Done-when and here; the kickoff confirms it.
6. **The stored status was not reopened.** This bundle derived Done, and
   extend mode would store Ready→Draft; the drafting run's instructions
   forbade any status flip, so the header rests at Ready and the delta is
   held by the `anchor re-review pending` park on Task 9 in `tasks.md`
   (Tasks 10–12 wait behind it through their edges, and the freshness gate
   refuses dispatch on the moved anchor in any case). The kickoff removes
   the park at sign-off, or applies the reopen instead.

## Changelog

- 2026-10-25 — Extension drafted via `/spec-draft --extend invariant-tasks`
  (meaning-class, awaiting kickoff): per-task repositories as
  format-version 3. New REQ-F1.1–REQ-F1.8, D-13–D-15, Tasks 9–12, and
  their test-spec entries; scope lines marked as the extension's. Routed
  here by mission-control Task 12 (mission-control D-22); seeded by the
  repository-field pending note and obs:74a7f907. Drafted unattended, so
  every choice an operator would have made is listed under *Open questions
  for the kickoff*.
- 2026-08-26 — Expression-only amendment riding format-grammar Task 4
  (format-grammar REQ-A1.9, REQ-E1.3). Two edits, neither changing an
  accepted decision:

  REQ-C1.5's severity phrasing said the v2 invariants are enforced "as errors
  on non-Draft v2 bundles". Read literally that covers Retired and Superseded,
  which the shipped validator warns on and this bundle's own test-spec entry
  for REQ-C1.5 pins as warnings. The phrasing now names the severities
  directly — errors on the signed-off live statuses, warnings on Draft and on
  the terminal records — per the carried bootstrap D-25 severity model. No
  behavior, test, or fixture changes; the sentence now says what was already
  decided and already shipped.

  The Deferred entry's free-text gate carried a parenthetical enumerating the
  condition grammar's status literals, ending "notably not ready". That
  enumeration was a copy of a fact the taxonomy doctrine owns, and
  format-grammar Task 4 added `ready` to the evaluator's stored-status
  whitelists, making the copy false. The parenthetical now points at the
  doctrine doc instead of restating it. The gate CONDITION is untouched, so
  the entry surfaces for a human each sweep exactly as before.

  This entry also closes the ritual owed for the gate's earlier conversion
  from `GATE(when:)` to free-text form (2026-07-26, PR #321), which landed the
  rewrite without a changelog line or a re-anchor entry. That conversion was
  expression-only on the same grounds: the two clauses are preserved verbatim
  and the gate was never machine-evaluated in either form (the structured form
  reported MALFORMED because no atom parsed; the free-text form surfaces
  unevaluated by definition), so no verdict moved.

- 2026-07-15 — Migrated to format-version 2 (D-10, REQ-D1.3;
  one-shot `scripts/migrate-format-version.sh` run): placement sections
  collapsed into a single `## Tasks` section, state annotation bullets
  stripped, stored header restricted to the human-gated set, the
  `**Execution:**` pointer line added, `Format-version:` bumped to 2 on
  all four files. Task definition lines are preserved byte-for-byte (the
  canonical `tasks.md` extraction digest is unchanged), so the required
  re-anchor rides as expression-only: the kickoff brief's self-re-anchor
  entry cites this entry. The `tasks.md` intro sentence was reconciled in
  the same change (the v1 "canonical orchestration state record" claim is
  false under v2; the file is the task-definition record and status is
  derived).

- 2026-07-15 — Completion-annotation supersession recorded (Task 8, D-11,
  REQ-C1.7). The normative completion annotation
  `Completed · PR #<n> merged <YYYY-MM-DD>` — stamped into the committed
  `tasks.md` by the level-triggered reconcile — does not apply to
  format-version 2 bundles: a v2 bundle commits no derived execution state,
  and completion is derived render content produced by the derivation engine
  at read time. The annotation has two normative homes, both scoped to v1 by
  this supersession: output-hygiene's `REQ-E1.2` contract
  (`specs/output-hygiene/requirements.md`, the origin), and the meta-spec's
  own 2026-07-10 versioning entry in `doctrine/spec-format.md` (which promoted
  the annotation to normative there too). Neither text is retroactively
  edited; the supersession is recorded via the ritual — D-11 plus this dated
  entry — and both homes remain normative for v1 bundles. Task 1's v2
  definition carries the v1-scoping of the `spec-format.md` entry.
- 2026-07-14 — Panel delta (gauntlet pass 2, gemini backend; brief
  Amendment 2; all five findings human-approved). Reference-bullet
  cross-section exclusivity (REQ-C1.5, D-3, test-spec C1.5); the
  unparseable-`Format-version:` case errors at every status, carved out of
  the Draft-warns arm (Task 2, REQ-C1.8); skill reconciliation
  version-keyed with v1 behavior preserved (REQ-E1.2, Task 7); the
  migration's re-anchor entry cites a dated changelog line the migration
  appends (REQ-D1.2, D-10, Task 6, test-spec D1.2); D-5's pointer-line
  text pinned as canonical, "e.g." dropped.
- 2026-07-14 — Self-review delta (gauntlet pass 1; brief Amendment 1).
  Done universe pinned for Deferred/Out-of-scope-parked tasks (D-4,
  REQ-B1.6); fail-closed version-keying extended to every version-keyed
  script (REQ-C1.8 coverage, Tasks 3–6); echo-sanitize scope broadened to
  evidence- and remote-derived text (REQ-C1.9, cross-cutting note); the
  derivation failure signal, absent-evidence boundary, and local-facts
  reporting defined (REQ-B1.5; REQ-B1.2 cross-reference); the migration
  atomic unit extended to cover the re-anchor entry (D-10, REQ-D1.2);
  halting-skill authorship named (REQ-A1.2, REQ-B1.4) and the orphan-park
  write target pinned to the main view (REQ-E1.2); parked-ness unified on
  reference bullets (D-8, Task 5); D-10's primary clause and the
  guard-first note aligned; the fleet queue added to D-12's consumer
  inventory; verification alignment across task Done-whens and test-spec
  entries; test-spec heading structure fixed (MD001). Applied as
  PS-1–PS-10 pending sign-off on the spec PR.
- 2026-07-14 — Kickoff walkthrough and sign-off lens pass (kickoff-brief
  §§2–7 and sign-off). Walkthrough edits: migration population widened to
  Draft/Ready/Active (REQ-D1.3, D-10, Task 6); REQ-A1.2 gained the
  "derived" qualifier and human-payload clause; REQ-C1.5 gained the
  pointer-line invariant (bullet integrity followed at the lens pass);
  D-4's Done clause restated to engine semantics; D-6's machine-surface
  clarification (§7). Lens-pass edits: REQ-B1.4 generalized with the
  read-surface limitation; REQ-D1.2 idempotency/atomicity; D-3 reference
  bullets generalized
  to all three human-payload sections; D-4 stored-status gating + zero-task
  rule; D-6 ported-derivation scope; D-7
  fail-closed version-keying; D-10 idempotency/atomicity + parked-block
  conversion; D-11 second normative home named; D-12 (no-cache decision)
  added; new REQ-B1.5, REQ-B1.6, REQ-C1.8, REQ-C1.9; REQ-E1.2 read-surface
  split; Goal/Sources argue the Maximal gate in its own terms and scope the
  kickoff-lifecycle deferral to its Active/Done half; task and test-spec
  alignment and strengthening throughout.
- 2026-07-14 — Initial draft elicited via `/spec-draft`. Fold-detection
  found the overlap with `orchestration-concurrency` (Done); the D-21
  spin-new triggers fired (meta-spec format change, independently ownable),
  so this is a new bundle citing that spec's D-1 Maximal deferral rather
  than a reopen-and-extend. Altitude trigger fired on the invocation's seed
  claims and was resolved as D-1 before design.

## Sources

- **Drafting invocation (2026-07-14).** The idea plus its pinned altitude
  seed claims: "make tasks invariant"; "infer their statuses without having
  to update files and markers". Both are we-keep-doing-X-manually altitude
  assertions; the gate fired and D-1 records the resolution.
- **orchestration-concurrency D-1 and its Deferred "Maximal variant"
  entry.** The sanctioned graduation this bundle executes: drop the
  committed `tasks.md` state sections, hold only stable task definitions,
  render status on demand. Its recorded gate — "the fleet spec surfaces a
  concrete need to drop the committed snapshot" — is evaluated in this
  bundle's Goal.
- **kickoff-lifecycle out-of-scope deferral.** "Fully deriving the bundle
  `Status:` header (dropping the stored value)" was explicitly deferred to
  the same Maximal graduation. This bundle completes the derivable
  (Active/Done) half; the stored human declarations are deliberately
  retained (D-4's rejected alternative records why full derivation was not
  taken).
- **orchestration-fleet live-derivation reads.** The meta-tower reads each
  spec's live derivation, not the committed snapshot — evidence the
  snapshot is becoming vestigial.
- **Machinery survey (drafting session, 2026-07-14).** A repo-wide
  read/write map of the volatile state layer: the derivation engine already
  computes full per-task status without reading committed sections; the
  committed layer has a single writer (`tasks-pr-sync.sh`); the `Dispatch`
  annotation has no live writer; the selector and gate evaluator are the
  two readers needing re-sourcing.
- **research: GitHub spec-kit.** The closest peer project tracks task
  status as manual markdown checkboxes; its issue #181 requests automatic
  completion tracking and discussions #152/#1804 describe spec staleness —
  the disease this bundle removes, unsolved in the ecosystem.
- **research: git-bug, git-task.** Git-native trackers solve conflict-free
  *storage* of state in git objects; state is still stored and updated, not
  derived from evidence — a different model, noted for contrast.
- **Operational evidence: shared-checkout deployment (2026-07).** A
  two-tower deployment sharing one checkout disabled state-move commits
  because concurrent committed state moves race on the shared index — the
  committed snapshot as a concrete operational liability.
- **mission-control D-22, REQ-H1.2 and Task 12 (2026-10-24).** The routed
  amendment this extension carries: a per-task repository field read by
  the dependency derivation, so each dependency's state comes from the
  repository it landed in.
- **Pending note `specs/_pending/invariant-tasks-repository-field.md`
  (2026-10-25).** The seed brief for this extension: the gap, what
  mission-control needs, and the questions the drafting answered.
- **obs:74a7f907** — a holder serving several work repositories cannot run
  a bundle whose tasks target different repositories: blocks name no
  repository, state derives from the launch repository, and splitting per
  repository loses the cross-repository edges. Its proposal (an optional
  per-task field resolved through machine-local config, state from the
  union of the bundle's repositories) seeds REQ-F.
- **custom-spec-location D-4 and its reverse-registry Deferred entry.** The
  marker that identifies a spec root, and the machine-local registry a
  later extension of that bundle builds; the alias this extension's field
  holds is a key into that registry.
