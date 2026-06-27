# Kickoff Lifecycle — Requirements

**Status:** Draft
**Last reviewed:** 2026-06-26
**Format-version:** 1

## Goal

planwright's lifecycle conflates two operator states that are not the same: a
spec that has been **kicked off** (signed off, validated, executable, with no
work started) and a spec that has been **started** (work in flight). Today
`/spec-kickoff` flips Draft→Active at sign-off, so "ready to execute" and
"executing" share one status. The distinction matters: a signed-off-but-unstarted
spec is exactly the state a human wants to see surfaced ("this is cleared for
takeoff, nothing has moved yet"), and the framework wants to gate on ("executable,
but the first dispatch has not happened").

This spec makes "kicked off" distinct from "started" through two coupled changes,
both expressing that kickoff completion is not execution start:

1. **Insert a `Ready` status between Draft and Active** (Draft → Ready → Active →
   Done). `/spec-kickoff` sign-off flips Draft→Ready (signed off, validated,
   executable, no work started — the meaning Active carries today at sign-off);
   the first `/orchestrate` dispatch flips Ready→Active (work in flight);
   Active→Done is unchanged. Active is thereby narrowed to mean strictly "work in
   flight".
2. **`/spec-kickoff` marks the spec PR ready, not draft, on clean completion.**
   The kickoff walkthrough *is* the review of the spec bundle, so once it is
   signed off and any configured verification has converged, the spec PR's state
   should reflect that the bundle is review-complete. Merge stays the human's
   reserved control (never auto-merge).

The Ready↔Active distinction is **derived**, not independently stored: a sibling
spec, `orchestration-concurrency`, already establishes that task state is a
derived projection of git/PR ground truth (its REQ-C1.1 derives each task as
Completed / In progress / Ready / Forward). This spec builds the bundle-level
Ready/Active distinction on that derivation — a bundle is Active iff any task
derives In-progress or Completed, else Ready when signed off — reconciled into the
bundle `Status:` header by the same single level-triggered writer, so there is no
second writer of derived state to drift.

## Scope

### In scope

- A sixth bundle status, `Ready`, inserted between Draft and Active: its
  definition, meaning, and the Draft→Ready→Active→Done transitions.
- The meta-spec (`doctrine/spec-format.md`) status table and transitions updated
  to the six-status lifecycle, reconciling bootstrap's lifecycle decisions via the
  supersede-pointer ritual (never reopening the Done bootstrap bundle).
- The status-aware validator: `Ready` recognized, and `Ready` findings treated as
  errors that block execution alongside Active and Done.
- The orchestration gate: "never act on a non-Active spec" becomes "never act on
  a spec that is not Ready or Active"; the Ready→Active transition on first
  dispatch implemented as a derived reconcile, not an independent stored flip.
- `/spec-kickoff` sign-off: flips Draft→Ready; marks the spec PR ready as the
  terminal step of clean completion; change-handling scales by lifecycle stage —
  a Ready bundle's pre-merge changes re-sign-off (delta re-walkthrough), the
  amendment ritual keys off Active (work in flight), a Done bundle reopens to Draft.
- The Ready↔Active derivation rule, implemented by extending
  `orchestration-concurrency`'s single level-triggered reconcile writer to
  reconcile the bundle `Status:` header.
- The bootstrap D-44 two-key model wording, updated: sign-off flips Draft→Ready and marks
  the spec PR ready; first dispatch flips Ready→Active; the human's merge
  activates the spec operationally.
- A narrow supersede of bootstrap D-26's "all framework-created PRs are drafts":
  the spec PR (and only the spec PR) is marked ready by kickoff on clean
  completion; task PRs stay drafts; merge stays human.
- Core status renderers that recognize Ready (the `/spec-walkthrough` stage-aware
  framing; status enumerations in validator and skill messages).
- Migration: existing signed-off-but-unstarted Active specs become Ready.

### Out of scope

- The cross-session inbox/heartbeat dashboard's Ready rendering. That dashboard is
  dotfiles-local overlay (bootstrap put it out of scope); core defines the Ready
  status, the overlay renders it (customization-boundary).
- A hardcoded "gauntlet" review step in core. The verification that precedes the
  ready-flip is the configurable review process (the `review_sequence`-class
  mechanism); a personal gauntlet is an overlay composition.
- Fully deriving the bundle `Status:` header (dropping the stored value and
  rendering it on demand). That is `orchestration-concurrency`'s deferred
  "Maximal" graduation; this spec keeps the stored snapshot and derives its
  Ready/Active content.
- Re-deciding `orchestration-concurrency`'s derivation internals; this spec
  consumes REQ-C1.1, it does not redefine it.
- Changing the task-level Ready / Forward / In-progress / Completed vocabulary
  that `orchestration-concurrency` defines; this spec consumes it.
- An automated spec-PR-thread resolution loop (a `/copilot-pairing`-style
  autopilot for spec-PR review threads). Spec-PR feedback is folded in by
  human-driven `/spec-kickoff` (delta re-walkthrough / re-sign-off, REQ-D1.4),
  not a dedicated core skill; the configurable review process (REQ-D1.5) is the
  only automation over the spec PR.
- Auto-merge at any tier (permanent carried invariant).

## REQ-A — The Ready status & lifecycle

- **REQ-A1.1** planwright SHALL recognize a sixth bundle status, `Ready`,
  positioned between Draft and Active, meaning: signed off, validated by the
  status-aware validator, executable, with no execution work started.
  *(Cites: D-1; bootstrap D-40, REQ-A1.6.)*
- **REQ-A1.2** The bundle lifecycle SHALL be Draft → Ready → Active → Done, with
  Retired and Superseded remaining human-set terminal states. `/spec-kickoff`
  sign-off SHALL flip Draft→Ready; the first `/orchestrate` dispatch (the first
  task to derive In-progress) SHALL result in Ready→Active; a spec SHALL transition
  to `Done` (from `Active`, or directly from `Ready` if all tasks complete at once)
  when its last Forward-plan / In-progress / Awaiting-input task moves to Completed
  (Done determination takes precedence over the Ready↔Active derivation, REQ-A1.5).
  *(Cites: D-1, D-2; bootstrap D-40, REQ-A3.1.)*
- **REQ-A1.3** `Ready` SHALL carry exactly the meaning bootstrap's `Active` carried
  at sign-off ("signed off and executable"), and `Active` SHALL be narrowed to mean
  strictly "execution work in flight". No spec SHALL be both signed-off-unstarted
  and labelled Active.
  *(Cites: D-1; bootstrap REQ-A1.6.)*
- **REQ-A1.4** The Draft→Ready transition SHALL be a stored, human-gated flip
  written by `/spec-kickoff` at sign-off; it SHALL NOT be derived from task state,
  because sign-off is a human gate, not an observable git fact.
  *(Cites: D-2.)*
- **REQ-A1.5** The Ready↔Active distinction SHALL be derived from task-state
  evidence per `orchestration-concurrency` REQ-C1.1: a bundle is `Active` iff at
  least one of its tasks derives to In-progress or Completed, otherwise `Ready`
  when signed off. This derivation applies only to bundles not already `Done`:
  Done determination (REQ-A1.2 — the last Forward-plan / In-progress /
  Awaiting-input task moving to Completed) takes precedence, so a fully-completed
  bundle derives `Done`, not `Active`. The bundle `Status:` header SHALL be
  reconciled to the derived value by the single level-triggered snapshot writer,
  never by an independent writer.
  *(Cites: D-2, D-3; orchestration-concurrency REQ-C1.1, D-1.)*
- **REQ-A1.6** The reopen cycle SHALL be updated: extending a Done bundle flips
  Done→Draft; scoped kickoff of the delta flips Draft→Ready (not directly to
  Active); the delta's Ready→Active follows the same derived rule as a fresh
  bundle.
  *(Cites: D-1; bootstrap REQ-A3.1.)*
- **REQ-A1.7** On adoption, planwright SHALL migrate every existing spec whose
  declared Status is `Active` but which has no task deriving In-progress or
  Completed to `Ready`; specs with any task in flight or completed SHALL remain
  Active. Thereafter the derived reconcile (REQ-A1.5) maintains the distinction.
  *(Cites: D-4; orchestration-concurrency REQ-C1.1.)*

## REQ-B — Validator & meta-spec format

- **REQ-B1.1** The meta-spec (`doctrine/spec-format.md`) status table and
  transitions SHALL be updated to the six-status lifecycle with `Ready` defined and
  the Draft→Ready→Active→Done transitions stated. bootstrap's lifecycle decision
  (D-40), two-key decision (D-44), and all-drafts/non-Active decision (D-26) SHALL
  be reconciled via the supersede-pointer ritual — annotated `Superseded-by:` and
  landed in this spec's PR — never by reopening the Done bootstrap bundle.
  *(Cites: D-1, D-5; orchestration-concurrency D-5; bootstrap D-40, D-44, D-26.)*
- **REQ-B1.2** The status-aware validator SHALL recognize `Ready` as a known
  status and SHALL treat `Ready` findings as errors that block execution,
  alongside Active and Done (Ready is signed-off live content). Draft findings stay
  warnings; Retired and Superseded stay frozen-record warnings.
  *(Cites: D-1; bootstrap D-25, REQ-A2.1.)*
- **REQ-B1.3** The validator SHALL accept Draft→Ready, Ready→Active, Active→Done,
  and Done→Draft (reopen) as valid status transitions and SHALL preserve
  terminal-state discipline (no transition out of Retired or Superseded).
  *(Cites: D-1; bootstrap REQ-A3.1.)*

## REQ-C — Orchestration gates

- **REQ-C1.1** `/orchestrate` SHALL act on a spec whose status is `Ready` or
  `Active`, superseding the "non-Active" refusal; it SHALL continue to refuse
  Draft, Done, Retired, and Superseded specs, SHALL NOT auto-chain into
  `/spec-kickoff`, and SHALL provide no bypass flag. A `Ready` spec is acted on
  once merged to main — the same on-main ground truth `/orchestrate` has always
  read; the "nothing executes against the spec until merge" rule (D-6, D-7) scopes
  the pre-merge spec-PR window, not the on-main `Ready` state.
  *(Cites: D-1; bootstrap REQ-F1.4, REQ-J1.2, D-26.)*
- **REQ-C1.2** On the first dispatch that creates In-progress evidence for a Ready
  spec, the bundle SHALL transition Ready→Active via the derived reconcile
  (REQ-A1.5), implemented by extending `orchestration-concurrency`'s single
  level-triggered reconcile writer; no independent status writer SHALL be
  introduced.
  *(Cites: D-2, D-3; orchestration-concurrency REQ-B1.3, D-1.)*
- **REQ-C1.3** The execution freshness gate and the Ready-or-Active gate SHALL
  compose: a Ready spec is executable only if its content anchor is execution-valid,
  exactly as an Active spec is today.
  *(Cites: D-1; bootstrap REQ-F1.9.)*

## REQ-D — Kickoff sign-off & spec-PR ready-flip

- **REQ-D1.1** `/spec-kickoff` sign-off SHALL flip Draft→`Ready` (not Active),
  bump `Last reviewed`, write the sign-off record with the content anchor last,
  and mirror the Status across all four spec files.
  *(Cites: D-1, D-6; bootstrap REQ-B2.4, D-44.)*
- **REQ-D1.2** On clean kickoff completion, `/spec-kickoff` SHALL mark the spec PR
  ready (un-draft) as the terminal step, after any configured verification over the
  bundle has converged. It SHALL NOT mark the PR ready if sign-off parked on a fork
  or the configured verification did not converge. Merge remains the human's
  reserved control; the skill SHALL never auto-merge.
  *(Cites: D-6, D-7; bootstrap D-26, D-44, REQ-J1.1.)*
- **REQ-D1.3** The spec PR SHALL be the only framework-created PR a skill marks
  ready; all task PRs SHALL remain drafts. bootstrap D-26's "all framework-created
  PRs are drafts" SHALL be narrowly superseded to this effect via the
  supersede-pointer ritual, and a config opt-out (`mark_spec_pr_ready_on_kickoff`,
  default true) SHALL gate the flip.
  *(Cites: D-5, D-6; bootstrap D-26, REQ-F1.6.)*
- **REQ-D1.4** `/spec-kickoff` SHALL scale change-handling to what is built
  against the contract. A `Ready` bundle (signed off, no execution work started,
  spec PR pre-merge) SHALL take changes — PR feedback or any other pre-merge edit —
  through **delta re-walkthrough / re-sign-off**, not the amendment ritual: an
  expression-only change takes a changelog entry and a self-re-anchor; a meaning
  change takes a delta-scoped walk, the delta lens pass, a re-sign-off, and a fresh
  anchor; the spec PR stays ready throughout (it is the review surface). The
  amendment ritual (with its in-flight task-PR coordination) SHALL apply once the
  bundle is `Active` (work in flight). A `Done` bundle SHALL reopen to Draft per the
  reopen cycle (REQ-A1.6).
  *(Cites: D-1, D-6, D-7; bootstrap D-44, REQ-A3.1, REQ-A3.3.)*
- **REQ-D1.5** The verification that precedes the ready-flip (the process a user
  may informally call a "gauntlet") SHALL be expressed as the configurable
  review process (the `review_sequence`-class mechanism), not a hardcoded core
  step. When an overlay runs such a pass over the spec PR, the ready-flip
  (REQ-D1.2) SHALL be its terminal step; the flip primitive lives in core, whether
  an extra review pass precedes it is configurable.
  *(Cites: D-7; customization-boundary; bootstrap REQ-D1.3.)*

## REQ-E — Downstream status surfaces & boundary

- **REQ-E1.1** Core status renderers SHALL recognize `Ready`: `/spec-walkthrough`'s
  stage-aware framing SHALL frame the Ready stage, and validator and skill messages
  that enumerate statuses SHALL include Ready.
  *(Cites: D-1; spec-comprehension REQ-A1.4; bootstrap REQ-A2.1.)*
- **REQ-E1.2** Core SHALL expose `Ready` as a first-class, substrate-agnostic
  status value that any attention surface can render; the specific cross-session
  inbox/heartbeat dashboard rendering of a Ready/signed-off state SHALL remain an
  overlay concern, not core, per the capability-vs-style boundary.
  *(Cites: D-8; customization-boundary; bootstrap (Scope — out of scope).)*

## Changelog

- 2026-06-27: Kickoff walkthrough edits. Reworked REQ-D1.4 to a weight-scaled
  change-handling model (a Ready bundle's pre-merge changes re-sign-off via delta
  re-walkthrough; the amendment ritual keys off Active; Done reopens) and recorded
  the principle in D-6/D-7. Added an Out-of-scope bullet ruling out an automated
  spec-PR-thread resolution loop (spec feedback is human-driven `/spec-kickoff`).
  Added a design note clarifying that validator enforcement is execution-gated, not
  CI-gated, so no-CI adopters still validate any spec they execute.
- 2026-06-26: Draft bundle elicited via `/spec-draft kickoff-lifecycle`. Four
  decisions taken interactively: spin a new bundle (not reopen bootstrap); model
  Ready as a stored Draft→Ready human flip plus a derived Ready↔Active reconcile
  consuming `orchestration-concurrency` REQ-C1.1; kickoff marks the spec PR ready
  as the terminal step after configurable verification; the Ready↔Active
  derivation extends `orchestration-concurrency`'s single reconcile writer as a
  hard cross-spec dependency.

## Sources

- **The `/spec-draft kickoff-lifecycle` invocation brief (drafting session,
  2026-06-26).** The two coupled changes (insert Ready; kickoff marks the spec PR
  ready) and the scope-to-update list. Frames REQ-A, REQ-C, REQ-D.
- **The `bootstrap` spec bundle (`specs/bootstrap/`).** Owner of the lifecycle and
  PR-flow decisions this bundle changes: `bootstrap D-40` (five-status lifecycle),
  `bootstrap D-44` (two-key spec-PR flow), `bootstrap D-26` (hard invariants,
  all-drafts, non-Active gate), `bootstrap D-25` (status-aware validator), and
  `bootstrap REQ-A1.6 / REQ-A2.1 / REQ-A3.1 / REQ-B2.4 / REQ-F1.4 / REQ-F1.6 /
  REQ-F1.9 / REQ-J1.1 / REQ-J1.2`.
- **The `orchestration-concurrency` spec bundle
  (`specs/orchestration-concurrency/`).** Establishes the derived-projection model
  this bundle builds on: `orchestration-concurrency REQ-C1.1` (task-state
  derivation, including a task-level Ready), `orchestration-concurrency D-1`
  (progress state is a derived projection; prior art: Kubernetes level-triggered
  reconciliation, event-sourcing read-model projections, git reachability-derived
  state, the Terraform mutable-state-file anti-pattern), `orchestration-concurrency
  REQ-B1.2 / REQ-B1.3` (the single level-triggered writer and derived snapshot),
  and `orchestration-concurrency D-5` (the supersede-pointer ritual for touching a
  Done bundle's decisions without reopening it — the precedent this bundle reuses).
- **The `spec-comprehension` spec bundle (`specs/spec-comprehension/`).** Downstream
  consumer: `spec-comprehension REQ-A1.4` (render bundles in any status), the
  stage-aware framing that must learn the Ready stage.
- **The `customization-boundary` doctrine.** Governs the core-vs-overlay call for
  the heartbeat/dashboard Ready rendering (REQ-E1.2, D-8) and the configurable
  verification (REQ-D1.5, D-7).
- **drafting-session decision (2026-06-26): kickoff marks the spec PR ready.**
  Settled direction that the spec PR's ready state should reflect the completed
  kickoff review, with merge remaining the human's key.
