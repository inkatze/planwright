# Kickoff Lifecycle — Design

**Status:** Draft
**Last reviewed:** 2026-06-26
**Format-version:** 1

Origin-tag legend: `N` new decision; `C, <foreign D>` carried from another
bundle; `extends <foreign D>` builds on a sibling decision without overturning
it. Foreign decision IDs are namespace-qualified (`bootstrap D-40`,
`orchestration-concurrency D-1`).

## Decision log

### D-1: Insert `Ready` between Draft and Active; kicked-off ≠ started  (N)

**Decision:** Add a sixth bundle status, `Ready`, between Draft and Active.
`Ready` means "signed off, validated, executable, no work started" — the meaning
bootstrap's `Active` carries the instant `/spec-kickoff` signs off. `Active` is
narrowed to mean strictly "execution work in flight". The lifecycle becomes
Draft → Ready → Active → Done (Retired/Superseded terminal as before).

**Alternatives considered:**
- Keep five statuses and overload `Active` for both signed-off-unstarted and
  in-flight. Rejected because: that is exactly the conflation this spec exists to
  remove — a human reading the dashboard and a gate reading the status both want
  to distinguish "cleared, nothing moved" from "moving".
- Signal the distinction only at the task-section level (no bundle status),
  reading "any task in progress?" ad hoc. Rejected because: the bundle `Status:`
  is the value humans, gates, validators, and dashboards read first; a task-only
  signal does not surface "this whole spec is ready" anywhere a reader looks.

**Chosen because:** a single new state names the signed-off-but-unstarted
condition with the minimum addition, and the pattern is well-precedented in
mature lifecycles that separate "accepted" from "shipped" (PEP Accepted vs Final,
KEP implementable vs implemented, TC39 Stage-4-accepted vs shipped). bootstrap's
own D-40 survey of six mature processes is the framing source; this adds the one
state those processes have that planwright still lacked at the
accepted-vs-in-flight boundary.

### D-2: Draft→Ready is a stored human flip; Ready↔Active is derived  (N)

**Decision:** Treat the two transitions by their nature. Draft→Ready (sign-off)
is a **stored, human-gated flip** written by `/spec-kickoff`: sign-off is a human
act, not an observable git fact, so it must be recorded, not derived. Ready↔Active
("has work started?") is **derived** from task-state evidence, because "work
started" *is* observable (an open PR, a task branch with commits, a fresh dispatch
marker — `orchestration-concurrency` REQ-C1.1).

**Alternatives considered:**
- A stored flip for both transitions (an explicit `/orchestrate` Ready→Active
  status write on first dispatch). Rejected because: a stored Ready→Active flip is
  a second writer of derived state, which can drift from git truth — the
  Terraform mutable-state-file failure mode `orchestration-concurrency` D-1
  explicitly avoids — and it duplicates the "is this task in progress?" judgement
  the derivation engine already owns.
- Derive both transitions, including sign-off. Rejected because: you cannot derive
  "signed off" from task state; sign-off is the human's first key. Deriving it
  would erase the human gate the whole lifecycle rests on.

**Chosen because:** derive what is observable, store what is human-gated. This
keeps exactly one stored, human-authored transition (sign-off) and makes the rest
of the bundle-status motion a projection of ground truth, consistent with
`orchestration-concurrency`'s model.

### D-3: Implement Ready↔Active by extending the single reconcile writer  (extends orchestration-concurrency D-1)

**Decision:** The bundle `Status:` header's Ready/Active value is **derived
content**, like `tasks.md` section placement, reconciled by
`orchestration-concurrency`'s single level-triggered writer (its REQ-B1.2/B1.3).
That writer is extended to compute the bundle status (Active iff any task derives
In-progress or Completed, else Ready when signed off) and reconcile the `Status:`
header across the four files. No new writer of derived state is introduced; the
single-writer invariant is preserved. This makes the dependency on
`orchestration-concurrency`'s derivation engine (its Task 1) and reconcile writer
(its Task 4) a **hard, sequencing dependency** for this spec's REQ-A1.5 / REQ-C1.2.

**Alternatives considered:**
- A separate Ready→Active writer inside `/orchestrate`, independent of the
  reconcile. Rejected because: two writers of derived snapshot content is the
  exact drift hazard `orchestration-concurrency` exists to remove; it would
  reintroduce the bug a sibling spec is mid-flight fixing.
- Interim stored flip now, collapse into the derived reconcile later (ship this
  spec independently of `orchestration-concurrency`). Considered and rejected by
  the human at drafting: it introduces a temporary second writer and throwaway
  code, in tension with the single-writer invariant, for the sake of decoupling
  from a sibling that is already specified and merged.

**Chosen because:** one writer of derived state is the invariant the concurrency
work establishes; extending it (rather than racing it) keeps that invariant whole
and avoids throwaway. The cost is an explicit sequencing dependency, recorded in
the task graph (Task 6 `Dependencies:`) and this design's Cross-cutting concerns.

### D-4: Migration is the derived reconcile, plus a one-time sweep  (N)

**Decision:** On adoption, every spec whose declared Status is `Active` but which
has no task deriving In-progress or Completed is migrated to `Ready`; specs with
work in flight or completed stay Active. Because Ready↔Active is derived (D-3), the
reconcile *is* the migration once it lands — running it over each existing bundle
computes the correct value. A one-time sweep applies it at adoption to whichever
bundles are then `Active` with no task in flight (for example
`orchestration-concurrency`, in-tree today; and `orchestration-fleet` if it has
merged by then), which become `Ready`.

**Alternatives considered:**
- Leave existing Active specs labelled Active. Rejected because: they would be
  mislabeled the moment Ready exists — `orchestration-concurrency` is the live
  example (Active, zero tasks started).
- Require a manual re-kickoff of each Active spec to re-emit Ready. Rejected
  because: disproportionate; the derived rule already computes the right value
  from ground truth.

**Chosen because:** the migration falls out of the derivation for free; the sweep
is a thin one-time application of the same rule, not a separate mechanism.

### D-5: Touch bootstrap's Done decisions via supersede-pointer, not reopen  (C, orchestration-concurrency D-5)

**Decision:** Reconcile the bootstrap decisions this spec changes — `bootstrap
D-40` (five-status lifecycle), `bootstrap D-44` (two-key spec-PR flow), `bootstrap
D-26` (all-drafts / non-Active gate) — by annotating each with a
`Superseded-by: kickoff-lifecycle D-<n>` pointer, landed in this spec's PR. The
Done bootstrap bundle is **never reopened**.

**Alternatives considered:**
- Reopen and extend bootstrap (`/spec-draft --extend`, Done→Draft, re-activate).
  Rejected because: disproportionate — it re-kickoffs the entire founding spec for
  a focused lifecycle refinement, and `orchestration-concurrency` D-5 already
  established the lighter ritual for exactly this situation.
- A forward-note only, leaving bootstrap's wording untouched. Rejected because:
  these are genuine meaning changes (six statuses; a PR-ready exception), so the
  relationship is recorded with the sanctioned supersede pointer, not an informal
  note.

**Chosen because:** supersede is the meta-spec's path for a meaning change to an
already-merged (Done) bundle; the pointers keep bootstrap and this spec consistent
on `main` without reopening a finished spec. This reuse is itself why the spec was
spun new rather than folded into bootstrap.

### D-6: Kickoff marks the spec PR ready; a narrow exception to bootstrap D-26's all-drafts rule  (N)

**Decision:** `/spec-kickoff` marks the **spec PR** ready (un-draft) on clean
completion. The kickoff walkthrough is the review of the spec bundle, so once the
bundle is signed off and any configured verification has converged, the spec PR's
ready state should reflect that. This carves a narrow exception to `bootstrap D-26`
("all framework-created PRs are drafts"): the spec PR, and only the spec PR, is
marked ready by a skill; task PRs stay drafts. Merge stays the human's second key
(never auto-merge). A config opt-out (`mark_spec_pr_ready_on_kickoff`, default
true) gates the flip.

**Alternatives considered:**
- Keep all PRs draft; the human un-drafts the spec PR by hand. Rejected because:
  the kickoff *is* the spec bundle's review — once it is signed off and verified,
  leaving the PR draft costs a redundant human keystroke with no added control,
  since merge is still the human's key.
- Mark every framework PR ready. Rejected because: task PRs still need their own
  execution review before they are ready; that is owned by the execution and
  review skills, not by this change.

Because nothing executes against the spec until merge, marking its PR ready does
not lock the bundle: pre-merge feedback re-sign-offs in place (D-7's weight-scaled
change-handling) while the PR stays ready. Once the human merges, that on-main
`Ready` bundle is what `/orchestrate` dispatches against (REQ-C1.1), flipping it to
`Active` on the first task; the "nothing executes until merge" rule scopes the
pre-merge window, not the merged `Ready` state.

**Chosen because:** the spec PR's ready state should track the completion of the
spec bundle's review (kickoff), exactly as a task PR's ready state should track
the completion of *its* review; the two-key model is preserved because merge
remains human.

### D-7: The ready-flip is the terminal step after configurable verification  (N)

**Decision:** The ready-flip (D-6) runs **last**, after any configured verification
over the bundle / spec PR has converged. The verification itself — the process a
user may informally call a "gauntlet" — is the configurable review process (the
`review_sequence`-class mechanism, bootstrap D-6 / REQ-D1.3), not a hardcoded core
step. In bare core, `/spec-kickoff`'s own walkthrough and Discovery-Rigor lens
pass are that verification, and the flip follows them. When an overlay runs an
additional review pass over the spec PR, the flip is its terminal step.

Change-handling after the flip scales with what is built against the contract. A
Ready spec — signed off, spec PR readied, but with no execution work started — is
still under review until merge: pre-merge feedback on its PR is folded in by a
**delta re-walkthrough / re-sign-off** (expression-only: changelog + self-re-anchor;
meaning: delta lens pass + re-sign-off + fresh anchor), and the PR stays ready
throughout. The heavier **amendment ritual** — with its in-flight task-PR
coordination — is reserved for an `Active` spec, where execution is already reading
the brief; a merged (`Done`) spec changes via the supersede/reopen ritual. This is
why kickoff can mark the spec PR ready without committing to treat every later edit
as an "amendment": nothing executes against a Ready spec yet, so its review is
simply not finished until merge.

**Alternatives considered:**
- Treat any post-sign-off edit (Ready included) as an amendment, keyed off
  Ready-or-Active uniformly. Rejected because: the amendment ritual's weight is its
  in-flight-coordination machinery, and a Ready spec has nothing in flight — running
  it imports coordination concepts with nothing to coordinate. Weight should track
  what is built against the contract, not merely whether sign-off has happened.
- Hardcode a fixed review gauntlet in core before the flip. Rejected because: the
  review process is already configurable via `review_sequence`; hardcoding a
  second one duplicates it and bakes a personal preference into core
  (customization-boundary tilts this to overlay).
- Flip immediately at sign-off, before any PR-level verification. Rejected
  because: an operator who runs verification over the spec PR wants the flip after
  it converges; flipping first would mark the PR ready before its review
  completes.

**Chosen because:** flip-last composes with whatever verification the operator
configures, with a sensible bare-core default (kickoff's own review), and keeps
"gauntlet" out of core vocabulary as just one configuration of the existing
review mechanism.

### D-8: Heartbeat/dashboard Ready rendering stays overlay  (N)

**Decision:** Core defines `Ready` as a first-class, substrate-agnostic status
value any attention surface can render. The specific cross-session inbox/heartbeat
dashboard rendering of a Ready/signed-off state stays an **overlay** concern, not
core. The general capability (a status others can render) is core; the specific
dashboard rendering is overlay.

**Alternatives considered:**
- Pull the heartbeat Ready state into core. Rejected because: the entire
  inbox/heartbeat dashboard is out of bootstrap's scope and dotfiles-local;
  pulling one state into core while the surface it belongs to lives in the overlay
  is inconsistent.
- Say nothing about the dashboard. Rejected because: the invocation listed
  "dashboards/inbox heartbeat states" as a surface to update, so the boundary must
  be named explicitly to record what is core (the status value) and what is overlay
  (its dashboard rendering).

**Chosen because:** customization-boundary is explicit that a general capability
lands in core and a specific style stays in an overlay; naming the boundary keeps
core general and tells the dotfiles overlay exactly which value to render.

## Cross-cutting concerns

- **Two `Ready`s at two granularities.** `orchestration-concurrency` REQ-C1.1
  already uses `Ready` for a *task* state (dependencies met, no work started). This
  spec adds `Ready` as a *bundle* status. They are deliberately the same word at
  two scopes and compose cleanly: a bundle is Ready exactly when every task is
  task-Ready or task-Forward (none In-progress/Completed) and the bundle is signed
  off. Doctrine and skill prose name the scope ("task Ready" vs "bundle Ready")
  wherever ambiguity could arise.
- **Sequencing dependency on `orchestration-concurrency`.** REQ-A1.5 / REQ-C1.2
  (the derived reconcile) consume that spec's derivation engine (its Task 1) and
  single reconcile writer (its Task 4), which are specified but not yet built (all
  eight of its tasks are in Forward plan). The task graph encodes this as a hard
  cross-spec dependency; the human-gated and validator/meta-spec/docs work
  (REQ-A1.1–A1.4, REQ-B, REQ-D, REQ-E) does not depend on it and can land first.
- **Single-writer invariant.** Per D-3, no skill other than the extended reconcile
  writer mutates the bundle `Status:` Ready/Active value. `/spec-kickoff` writes
  the one human-gated transition (Draft→Ready, and the reopen Done→Draft); the
  reconcile owns Ready↔Active and Active→Done's derived rendering.
- **Change-handling weight scales by lifecycle stage** (D-6, D-7; REQ-D1.4). The
  cost of changing a spec tracks what is built against its contract, not merely
  whether it was signed off: **Draft** edits are plain authoring; a **Ready** spec
  (signed off, PR pre-merge, no work started) re-sign-offs pre-merge changes via a
  delta re-walkthrough (expression: changelog + self-re-anchor; meaning: + delta
  lens pass), PR staying ready; an **Active** spec uses the full amendment ritual
  with its in-flight task-PR coordination; a **Done** spec supersedes/reopens. The
  lens pass still fires on a meaning change to a Ready spec — a Ready bundle is
  about to be merged-and-executed, so a wrong spec is exactly what the lens pass
  guards (bootstrap D-45); what is dropped at the Ready stage is the *coordination* overhead,
  not the *correctness* check.
- **Enforcement is execution-gated, not CI-gated.** The status-aware validator
  blocks *execution*, not merge (REQ-B1.2): it runs inside `/spec-kickoff`
  (pre-flight, and re-run under enforcement at sign-off, which refuses to record
  while errors remain), and the freshness gate (REQ-C1.3) forces a re-sign-off
  before the next dispatch. So a planwright adopter with **no CI gate** still gets
  full structural + semantic validation of any spec it executes, at re-sign-off
  time. A CI gate (planwright's guard-catalog `check:specs`, wired via the `builder`
  skill) is an additional, earlier, merge-blocking tripwire — recommended, not a
  dependency. Without it, a malformed or stale-anchor spec can merge, but cannot be
  executed (kickoff sign-off enforcement and the freshness gate both fail closed).
