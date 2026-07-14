# Invariant Tasks — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-14
**Format-version:** 1

## Goal

`tasks.md` today mixes two kinds of content: invariant task *definitions*
(deliverables, done-when, dependencies) and volatile *state* (which section a
block sits in, `Status` / `Last activity` / `Dispatch` annotations, the bundle
`Status:` header). The state half is already a derived read-model snapshot
(orchestration-concurrency D-1): the derivation engine, not the committed
file, is the truth — yet every state change still means editing a committed
file: section moves, annotation stamps, reconcile commits, anchor churn, and
(on shared checkouts) index races that forced one deployment to disable
state-move commits outright. The snapshot earns its keep less and less: the
fleet meta-tower already reads the live derivation, not the committed file.

This bundle graduates to the sanctioned Maximal variant that
orchestration-concurrency deliberately deferred: the committed `tasks.md`
holds only invariant task definitions (plus the human-payload sections that
cannot be derived); all execution status is derived from git/PR ground truth
and rendered on demand, never committed. Fewer writes, no state drift by
construction, and the anchor/hook machinery that existed to tolerate state
churn simplifies or retires. The deliverable's altitude is recorded in D-1
(a format-capability graduation, landing as format-version 2 of the
meta-spec), per the altitude trigger the drafting invocation fired.

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
- Migration of this repo's live (Ready/Active) bundles to v2; Done and
  terminal bundles stay v1 untouched.

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

## REQ-A — The invariant committed ledger (format-version 2)

- **REQ-A1.1** Under format-version 2, `tasks.md` SHALL contain task
  definition blocks and human-payload sections only (Awaiting input,
  Deferred, Out of scope); it SHALL NOT carry committed placement sections
  (Forward plan / In progress / Completed) or state annotation bullets
  (Status / Last activity / Dispatch).
  *(Cites: D-2, D-3.)*
- **REQ-A1.2** A committed edit to a task block SHALL occur only for
  definition changes (via the amendment ritual); execution-state changes
  SHALL NOT produce commits to the bundle.
  *(Cites: D-2; orchestration-concurrency D-1 (Sources).)*
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
  first-class.
  *(Cites: D-6.)*
- **REQ-B1.3** For v2 bundles the render SHALL be the canonical
  execution-status read surface; skills and docs SHALL reference it rather
  than committed sections, and no derived-status artifact is committed or
  pushed to a remote mirror.
  *(Cites: D-6.)*
- **REQ-B1.4** A committed Awaiting-input entry SHALL be authoritative for
  its task's state in the derivation: human-authored parked state outranks
  git-evidence inference for that task.
  *(Cites: D-3.)*

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
- **REQ-C1.5** The validator SHALL enforce the v2 invariants — no state
  sections, no state annotations, stored header restricted to the
  human-gated set — as errors on non-Draft v2 bundles, keeping v1 rules for
  v1 bundles.
  *(Cites: D-7.)*
- **REQ-C1.6** No orchestration or execution act on a v2 bundle SHALL
  change its content anchor: state changes touch no committed spec file, so
  anchor churn from state movement is impossible by construction.
  *(Cites: D-9.)*
- **REQ-C1.7** The normative completion annotation SHALL be superseded for
  v2 bundles: completion is derived render content, and the supersession
  against output-hygiene's contract is recorded via the supersede ritual.
  *(Cites: D-11.)*

## REQ-D — Migration & coexistence

- **REQ-D1.1** A bundle's declared `Format-version:` SHALL select which
  rules and machinery apply; v1 bundles remain valid and operable
  indefinitely.
  *(Cites: D-7.)*
- **REQ-D1.2** A migration path SHALL convert a live v1 bundle to v2
  (collapse state sections into the single task list, strip state
  annotations, restrict the header, add the pointer line), preserving task
  definition lines byte-for-byte so the `tasks.md` canonical extraction is
  unchanged; the required re-anchor rides the migration as expression-only.
  *(Cites: D-10.)*
- **REQ-D1.3** planwright's own live (Ready/Active) bundles SHALL be
  migrated to v2; Done and terminal bundles SHALL stay v1 untouched.
  *(Cites: D-10.)*

## REQ-E — Doctrine, skills, and lineage

- **REQ-E1.1** `doctrine/spec-format.md` SHALL define format-version 2 via
  the meta-spec's own versioning ritual: the v2 `tasks.md` shape, the
  restricted stored-status vocabulary with the static pointer line, and
  derivation as the read surface.
  *(Cites: D-1, D-2, D-5.)*
- **REQ-E1.2** Every skill that writes or reads the committed state layer
  SHALL be reconciled for v2: `/spec-draft` authors v2 bundles;
  `/execute-task` drops the `Last activity` write; `/orchestrate`,
  `/resume`, and `/drain` read execution status through the render;
  Awaiting-input writes stay committed.
  *(Cites: D-6, D-7.)*
- **REQ-E1.3** Config knobs made vacuous for v2 (`commit_on_state_move`)
  SHALL be documented as v1-only in the options reference.
  *(Cites: D-7.)*
- **REQ-E1.4** orchestration-concurrency's Deferred "Maximal variant" gate
  entry SHALL be closed with an annotation citing this bundle as the
  graduation it was gating on.
  *(Cites: orchestration-concurrency Deferred gate (Sources).)*

## Changelog

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
  the same Maximal graduation.
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
