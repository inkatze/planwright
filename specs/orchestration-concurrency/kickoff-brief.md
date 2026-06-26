# Orchestration Concurrency — Kickoff Brief

> The durable contract between human and agent for this spec. Downstream
> skills (`/orchestrate`, `/execute-task`) operate from this brief, not by
> re-reading the spec bundle.

## 1. Header block

- **Spec path:** `specs/orchestration-concurrency`
- **Spec commit at walkthrough start:** `b0b132a`
- **Anchor at walkthrough start (preview):** `45b3621`
- **Walkthrough date:** 2026-06-26
- **Mode:** First activation (Status Draft, no prior brief)
- **Validator outcome (pre-flight, Draft = warnings):** `0 errors, 0 warnings`
- **Config:** `commit_on_kickoff: true` (default; no local override)
- **Decision-domains catalog:** resolved, 10 seed domains, no overlay additions
- **Doctrine docs resolved:** spec-format, discovery-rigor, validation-rigor,
  security-posture, decision-domains, interaction-style

<!-- Sections 8 (sign-off) and 9 (amendment log) are written by the
     sign-off flow. -->

## 2. Goal & glossary

### Goal (agent's restatement)

Concurrent orchestration — multiple `/orchestrate` towers across different
specs sharing one checkout, or across multiple tasks of one spec — currently
corrupts shared orchestration state in three observed ways: the `tasks.md`
ledger mis-sorts, dispatch metadata lands on the wrong task block or
duplicates (the `>1 Status line` signature), and worker branches inherit
sibling/foreign-spec dispatch commits as ancestors (polluting the worker PR
diff). The only repair today is manual (merge intermediate PRs to flush
unpushed local-`main` bookkeeping; hand-resort the ledger).

The fix is architectural: orchestration progress stops being hand-maintained
mutable state each tower edits, and becomes a **derived projection** of
observable git + GitHub evidence. The committed `tasks.md` sections become a
discardable, rebuildable read-model snapshot (event-sourcing read-model
pattern); placement is recomputed idempotently and level-triggered from truth
(Kubernetes controller pattern); a missed event self-heals on the next
reconcile. Because `main` carries no dispatch commits, a worker worktree cut
from it inherits nothing foreign — contamination is impossible **by
construction**, not merely mitigated.

This is the **state-safety foundation** of a two-spec family; the scaling /
resilience / UX layer is the sibling `orchestration-fleet` spec, which
consumes this contract.

### What it rules out (scope, confirmed)

- Scaling / resilience / UX layer (pluggable+autodetected backends,
  self-management, meta-orchestration, **inter-orchestrator coordination
  protocol**, approachability) → `orchestration-fleet`.
- Anchor-drift / kickoff-freshness false-halts (a distinct subsystem: the
  brief↔content anchor, not the ledger) → separate fast-follow.
- Auto-merge at any tier → permanent human-reserved control, carried in.
- Selection *policy* (critical-path / guard-first ordering) → unchanged; this
  spec changes how state is *represented and derived*, not which unit is
  *chosen*.
- The Maximal variant (drop the committed `tasks.md` snapshot entirely) →
  deferred as a sanctioned future graduation (D-1), not built here.

### Assumptions

- **No-remote is first-class.** Derivation falls back to local git + the
  runtime marker alone; `origin`/PR signals are used when present, never
  required. Solo/prototyping is a supported path, not degraded.
- git's native trailer mechanism and reachability checks are available and
  authoritative.

### Deliberate non-edge: towers are shared-nothing; coordination unnecessary by design

Towers do **not** message each other, and this is intentional, not an
oversight. They coordinate implicitly through shared ground truth (git +
GitHub), the way Kubernetes controllers converge on observed state without a
chat protocol. No tower writes authoritative state at dispatch, so there is
nothing to coordinate a write to. The two residual races are handled without
messaging: double-dispatch is closed by selection reading *live* derivation
(Task 5) plus the per-spec lock; concurrent reconcile writes are serialized by
the per-spec lock and made order-independent by idempotent level-triggered
recompute. The per-spec advisory lock is mutual exclusion on a critical
section, **not** a message channel. A real inter-orchestrator coordination
*protocol* (towers negotiating/dividing work, a tower-to-tower bus,
meta-orchestration) is explicitly an `orchestration-fleet` concern. **Do not
"add a coordination protocol" to this spec thinking it was a missing piece;
the design dissolves the need for one.**

### Glossary (implicit terms)

| Term | Working definition |
| --- | --- |
| Derived projection / read-model snapshot | Committed `tasks.md` sections are a cache recomputed from truth, never authoritative; discardable and rebuildable. |
| Level-triggered | Reconcile recomputes *full* placement from current observed state, not per-event deltas; re-run on unchanged truth is a no-op. |
| Dispatch record | Proof of dispatch = the task branch (first durable act) + the per-spec advisory lock. No `tasks.md` write. |
| Runtime dispatch marker | Durable, timestamped local marker in the advisory-lock dir; covers the window between branch-create and the branch acquiring its first commit (a zero-commit branch is not yet evidence); superseded by branch evidence once the branch carries a commit. A stale orphan marker (past the staleness threshold, no commits) reverts the task to Ready. |
| `Planwright-Task` trailer | A `Planwright-Task: <spec>/<id>` commit-footer trailer (like `Signed-off-by:`); the durable completion anchor surviving branch deletion and solo direct-to-`main` commits. |
| Authoritative evidence | Ordered signal set {PR/merge state, commit/branch reachability, trailer, runtime marker}; git ground truth takes precedence. |
| Tower | One running `/orchestrate` instance (a stateless step machine). |

Signed off: 2026-06-26

## 3. Requirements walkthrough

Five REQ groups walked; intent confirmed for A, B, C, D, E. Lens walk surfaced
five findings; four carried decisions (one revealed a latent requirement↔test
contradiction), one resolved as a recorded clarification.

### Per-group outcomes

- **REQ-A (dispatch isolation, derived state, no-remote).** Confirmed. Dispatch
  writes no `tasks.md`; branch + lock are the record; worker base carries no
  dispatch commits; no-remote is first-class.
- **REQ-B (single idempotent projector).** Confirmed, with the placement-vs-
  definition boundary and atomic-write clarifications applied (findings ④, ⑤).
- **REQ-C (derivation & conflict resolution).** Confirmed. Squash/rebase edge
  recorded as a risk (finding ③), no requirements change.
- **REQ-D (advisory lock).** Confirmed. Branch-ref-as-fence holds; the
  reconcile-write atomicity finding (⑤) backs the stale-break reasoning.
- **REQ-E (corruption & drift guards).** Re-scoped: the drift guard targets
  **structural corruption**, not placement freshness (finding ①). This corrected
  a contradiction with test-spec REQ-E1.1.

### Findings & decisions

1. **Drift guard vs. intentional snapshot lag (REQ-E1.1).** Decision:
   **structural-corruption only** — the guard fails on signatures reconcile
   would never produce (wrong-block, mis-sort, malformed/duplicate); it does not
   fail on a well-formed snapshot lagging live truth. Reconcile owns freshness
   (REQ-B1.2). *Caught and fixed a latent requirement↔test contradiction:*
   test-spec REQ-E1.1 said "out of sync fails," which contradicted this; both
   `requirements.md` and `test-spec.md` REQ-E1.1 were realigned.
2. **D-3 marker window (design↔REQ contradiction).** Decision: **branch-first
   stands; reword D-3.** The marker covers **branch-create → first-commit** (a
   zero-commit branch is not yet evidence per REQ-C1.1), not lock-acquire →
   branch-create. Branch-first is fail-safe. D-3 prose corrected.
3. **Squash/rebase merge completion (REQ-C1.1/C1.2).** Decision: **risk row +
   rely on `gh`/trailer**, no requirements change. With a remote, merged-PR-via-
   `gh` covers it; for solo, squash needs trailer preservation — documented in
   Task 8 docs and recorded as risk R3 (§7).
4. **Sole-writer boundary (REQ-B1.1).** Resolved as a clarification: "sole
   writer" governs section *placement*, distinct from task-*definition*
   authoring (`/spec-draft`, `/spec-kickoff`); `/orchestrate` and `/execute-task`
   write no placement. REQ-B1.1 prose clarified.
5. **Atomic snapshot write under racy stale-break (REQ-D1.2).** Decision:
   **require atomic write-temp-rename.** Added to REQ-B1.1 and Task 4 Done-when,
   so concurrent reconciles cannot tear `tasks.md`.

### Consolidated spec-edit list (applied in place, Draft bundle)

- `design.md` D-3: reworded the runtime-dispatch-marker window to branch-create →
  first-commit, with the fail-safe rationale. *(finding ②)*
- `requirements.md` REQ-E1.1: re-scoped to structural corruption; excluded
  intentional lag; freshness assigned to reconcile. *(finding ①)*
- `requirements.md` REQ-B1.1: placement-vs-definition boundary + atomic
  write-temp-rename. *(findings ④, ⑤)*
- `test-spec.md` REQ-E1.1: realigned to structural-corruption semantics; lagging
  well-formed snapshot passes; atomic-write assertion. *(findings ①, ⑤)*
- `tasks.md` Task 4 Done-when: atomic snapshot write. *(finding ⑤)*

Validator after edits: `0 errors, 0 warnings`.

Signed off: 2026-06-26

## 4. Design walkthrough

Reconciled D-ledger; every D-ID accounted for. One halting-class finding (⑥)
resolved by decision before sign-off.

| D-ID | Status | Note |
| --- | --- | --- |
| D-1 Derived projection, never committed at dispatch | Confirmed | Backbone. Citation corrected to extend bootstrap **D-2 and D-38** (finding ⑥). |
| D-2 Task reference via commit trailer | Confirmed | Squash-survival caveat → risk R3. |
| D-3 Reconciliation & selection mechanics | Amended | Marker window reworded to branch-create → first-commit (§3 finding ②). |
| D-4 One lock primitive; branch-ref is the fence | Confirmed | Atomic-write finding (⑤) reinforces the fence reasoning. |
| D-5 Reconcile bootstrap's contract | Amended | Retargeted from in-place amendment to **supersede** (finding ⑥). |

### Finding ⑥ — bootstrap-amendment ritual + D-1 citation (resolved)

Verified against `specs/bootstrap/`: **bootstrap is `Status: Done`**, and the
contract D-1 overturns is bootstrap **D-2** ("`tasks.md` doubles as the
orchestration state record"), not D-38 (control-tower dispatch).

1. **Ritual.** Decision: **supersede** (the Done-spec ritual). D-5 and Task 8
   rewritten: Task 8 annotates bootstrap D-2 with
   `Superseded-by: orchestration-concurrency D-1` (a pointer edit, no status
   change, no reopen), landing in this spec's own PR. The old plan (in-place
   `/spec-kickoff` amendment) was unexecutable because `/spec-kickoff` amendment
   mode requires Active, and the meta-spec routes post-merge meaning changes to
   supersede. Task 8's Done-when previously referenced "an Active bundle" that is
   actually Done — corrected.
2. **Citation.** Decision: **cite D-2 and D-38.** D-1 retagged
   `(N (extends bootstrap D-2 and D-38))` — D-2 is the state contract it
   overturns, D-38 the dispatch mechanics it changes.

### Consolidated spec edits (this section)

- `design.md` D-1: origin tag → `extends bootstrap D-2 and D-38`.
- `design.md` D-5: retitled "by supersede"; body rewritten to the supersede
  ritual with the Done-spec rationale and rejected alternatives.
- `tasks.md` Task 8: retitled "supersede"; deliverables/Done-when rewritten to
  the `Superseded-by` annotation (no reopen, no Active-bundle edit); squash
  caveat folded into the docs deliverable; citations add bootstrap D-2.

Validator after edits: `0 errors, 0 warnings`.

Signed off: 2026-06-26

## 5. Verification approach

### Coverage mix (15 REQs, all pinned)

- `[test]` only (10): A1.1, B1.2, B1.3, C1.1, C1.2, C1.3, C1.4, D1.2, E1.1, E1.2
- `[test + manual]` (2): A1.2, A1.3
- `[test + design-level]` (2): B1.1, D1.1
- `[design-level + test]` (1): E1.3

Every REQ carries a `[test]` arm; the suite is the spine. Mix leans
script-testable (portable shell over git/`gh` against fixture repos), which fits.

### Verification ownership (recorded in test-spec)

- `[test]` → CI via `mise run check`, per-PR gate.
- `[design-level]` → PR review (B1.1 sole-writer trace, D1.1 one-lock audit,
  E1.3 CI registration).
- `[manual]` → human-swept acceptance gates, timed per arm (finding ⑦):
  **A1.3** (solo no-remote) at **Task 3 PR-ready**; **A1.2** two-tower-at-scale
  as the **pre-Done capstone** on `main` after Tasks 3+4 (+7) merge. The
  automated `[test]` arm of A1.2 carries per-PR regression coverage meanwhile.

### Dead-path check

No dead paths. Confirmed (not flagged): A1.2's automated arm gives regression
coverage independent of the manual at-scale arm (harness built in Task 3);
C1.2's contradiction is testable as *emitted* before the Task 7 guard consumer
exists.

### Finding ⑦ — manual-sweep ownership (resolved)

Was unassigned. Decision (agent recommendation, human-accepted): human sweeps
the `[manual]` arms as acceptance gates with per-arm timing (above); CI owns
`[test]`, PR review owns `[design-level]`. Recorded durably in `test-spec.md`'s
intro. Minor deferral noted: C1.3's conflict-time regeneration *mechanism*
(merge driver vs. reconcile-on-conflict) is left to execution — a deliberate
choice, not a gap.

### Spec edit (this section)

- `test-spec.md` intro: added the Verification-ownership paragraph (CI / PR
  review / human-swept manual with per-arm timing).

Validator after edits: `0 errors, 0 warnings`.

Signed off: 2026-06-26

## 6. Task graph

Reconstructed from the authoritative `Dependencies:` lines.

```
T1 derivation engine        deps: —         2d   ┐ wave 1 (foundation)
T2 trailer emission         deps: —         0.5d │
T6 lock primitive           deps: —         1d   ┘
T3 dispatch rework          deps: 1, 6      2d   ┐
T4 reconcile (sole writer)  deps: 1         2d   │ wave 2 (after T1; T6 done)
T5 selection live truth     deps: 1         1d   │
T7 drift/corruption guards  deps: 1         1d   ┘
T8 docs + bootstrap supersede deps: 1,3,4   1d     wave 3 (join)
```

- **Waves:** W1 {T1,T2,T6} → W2 {T3,T4,T5,T7} (max width 4) → W3 {T8}.
- **Effort-weighted critical path = 5 days**, co-critical:
  `T1→T3→T8` and `T1→T4→T8`. T1 is the backbone; T8 the join.

### Deliberate non-edges

1. **T7 guard-first** is a should-precede preference, NOT a dependency (encoding
   it would invert the real T1 data dependency). Documented in tasks.md.
2. **T1 ⊥ T2.** T1 parses the trailer, T2 emits it; shared contract, not build
   order. T1 testable against fixture commits.
3. **T5 depends only on T1**, not T3/T4 — selection reads the derivation alone.
4. **T8 depends on T3+T4 but not T5/T6/T7.**
5. **T3+T4 joint sole-writer property (finding ⑧).** No T3↔T4 edge; the REQ-B1.1
   design-level sole-writer trace is owned by **T8** (depends on both). Recorded
   so nobody adds a spurious T4→T3 dependency.

### Finding ⑧ — joint sole-writer ownership (resolved)

Decision: **non-edge note + T8 owns verification.** Added the non-edge note to
tasks.md and assigned the REQ-B1.1 sole-writer trace to T8's Done-when.

### Spec edits (this section)

- `tasks.md` intro: added the joint-sole-writer deliberate non-edge note.
- `tasks.md` Task 8 Done-when: added ownership of the REQ-B1.1 design-level
  sole-writer trace.

Validator after edits: `0 errors, 0 warnings`.

Signed off: 2026-06-26

## 7. Risk register

### Decision-domains gap check (10/10 walked; catalog: 10 seed domains, no overlay)

| # | Domain | Verdict |
| --- | --- | --- |
| 1 | Data storage & modeling | Decided (snapshot/marker/trailer formats — D-1/D-2/D-3). No gap. |
| 2 | Caching | Decided (snapshot is a read-model cache; invalidation = level-triggered recompute). No gap. |
| 3 | Queues & async | Decided (idempotent reconcile, missed-event self-heal — REQ-B1.2). No gap. |
| 4 | API surface | Decided (trailer fully spec'd — D-2; script output is exec-detail). No gap. |
| 5 | Auth/authz | n/a (uses existing `gh`/git trust, no auth decisions). |
| 6 | Secrets & config | **Gap → R4** (stale-break + marker-staleness threshold values / safe defaults not pinned). |
| 7 | Concurrency | Core, mostly decided; **marker-lifecycle gap → resolved as finding ⑨ / R3**. |
| 8 | Observability | Decided (guards fail loudly; residuals captured in R1/R3). No separate gap. |
| 9 | Deploy & migration | **Gap → R5** (old/new dispatch coexistence during dogfooded rollout). |
| 10 | Dependency adoption | n/a (git/`gh` already used; native trailers). |

### Risk register

| ID | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | Solo + deleted branch + missing/typo'd `Planwright-Task` trailer ⇒ silent under-completion (§2). | Corruption guard flags a deps-met-but-no-evidence task; document the trailer convention prominently (Task 8). |
| R2 | Squash/rebase merge ⇒ branch-reachability fails; solo completion then depends on the trailer surviving the squash (§3 ③). | With a remote, merged-PR-via-`gh` covers it; document the squash caveat (Task 8). |
| R3 | Runtime marker wedge: a worker crashing between marker-write and first-commit could pin a task In progress (finding ⑨). | **Resolved in-spec:** timestamped marker + staleness threshold ⇒ stale orphan marker reverts the task to Ready (D-3, REQ-C1.1, Task 1/3). Early signal: stale-marker fixture test (test-spec REQ-C1.1). |
| R4 | New config (lock stale-break threshold, marker staleness threshold) lacks a pinned safe default; an operator who never reads it must still be safe. | Task 8 adds `docs/options-reference.md` rows; T6/T1 set or inherit a documented safe default; `check-options-reference.sh` gates it. |
| R5 | Dogfooded rollout: while T3/T4 are partially merged, old (commit-at-dispatch) and new (no-write) dispatch coexist on the same checkout. | Guard-first ordering (T7 before T3/T4/T5); land T3+T4 close together; A1.2 two-tower capstone sweep on `main` before the spec flips Done. |

No open questions remain; R1, R2, R4, R5 are accepted risks with recorded
mitigations, R3 is resolved in-spec.

### Finding ⑨ — marker lifecycle (resolved)

Decision: **timestamped marker + staleness threshold.** Applied to `design.md`
D-3, `requirements.md` REQ-C1.1, `tasks.md` Task 1 (deliverable + fixture matrix)
and Task 3 (timestamped marker), and `test-spec.md` REQ-C1.1 (stale-marker case).

### Spec edits (this section)

- `design.md` D-3: marker is timestamped; stale-orphan marker reverts to Ready.
- `requirements.md` REQ-C1.1: "fresh" marker holds In progress; stale marker ⇒
  Ready; citations add D-3, D-4.
- `tasks.md` Task 1: staleness check in derivation + stale-marker fixture case.
- `tasks.md` Task 3: writes a timestamped marker.
- `test-spec.md` REQ-C1.1: stale-marker-no-commits ⇒ Ready coverage.

Validator after edits: `0 errors, 0 warnings`.

Signed off: 2026-06-26

## 8. Sign-off

### Lens review pass (Discovery Rigor)

- **Scope:** full bundle (first activation).
- **Method:** parallel read-only sub-agent fan-out — 7 agents mapped to the 9
  canonical lenses (declared merges: error-handling+performance; naming+
  documentation). Already-dispositioned findings (①–⑨, R1–R5) excluded from
  re-reporting.
- **Tool grounding:** `spec-validate` clean (0/0); grep confirmed the bundle
  mandates no input validation / path containment and says nothing about `gh`
  *failing* (only absent).

#### Canonical lens-coverage table

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | none | Internally consistent; edge cases covered by ①–⑨. |
| Security | 4 → applied | Data-hygiene clean. Framework-script validation gap → new REQ-F1.1. |
| Error handling & failure modes | 2 → applied | `gh`-configured-but-failing → REQ-A1.3 clause; contradiction channel → REQ-C1.2 clause. |
| Performance | 0 actionable | Level-triggered full-recompute is deliberate (D-1); scale = fleet spec. Declined; logged to observations. |
| Concurrency / state | none | All hazards already dispositioned (①–⑨). |
| Naming, readability, structure | none | Terminology consistent. |
| Documentation | 2 → applied/dismissed | Formats fold into REQ-F1.1; Task 8 docs-target named; sign-off-block "incomplete" = false positive (this very flow writes it). |
| Tests / verification | 1 → applied | Branch-first ordering + fail-safe added to test-spec A1.1; remainder design-level/already-deferred. |
| Cross-file consistency | 1 → fixed | Brief §2 glossary marker-window was stale; corrected. |

#### Dispositions

- **Cluster B (security-posture) — APPLIED as a new requirement.** Added
  **REQ-F — Robustness & framework-script safety** (REQ-F1.1): parsed
  identifiers validated against their grammar before use; derived marker/lock
  paths containment-checked; malformed/hostile input refused. Test-spec REQ-F1.1
  added; folded into T1/T3/T6 Done-whens + citations.
- **Cluster C (failure modes) — APPLIED as clauses.** REQ-A1.3: a
  configured-but-failing `gh` degrades to git-only and surfaces, never wedges.
  REQ-C1.2: contradictions surface on a defined output-stream channel that exists
  independently of the guard being wired. Test-spec A1.3 + C1.2 arms added; T1
  Done-when updated.
- **Cross-file glossary — APPLIED (fixed).** Brief §2 marker-window glossary row
  corrected to branch-create → first-commit + timestamped/stale note.
- **Test tightening — APPLIED.** Branch-first ordering + fail-safe assertion
  added to test-spec REQ-A1.1.
- **Docs target — APPLIED.** Task 8 names the `docs/` derived-state doc +
  `docs/options-reference.md` rows.
- **Performance — DECLINED (with rationale).** Level-triggered full-recompute is
  the deliberate D-1 choice; scale/cost-bound is the `orchestration-fleet` spec's
  job. Logged a degradation-point observation to
  `specs/_observations/opportunities.md` (2026-06-26).
- **Sign-off-block "incomplete" — DISMISSED.** False positive: the section was
  mid-write by this sign-off flow.

#### Lens-pass spec edits

- `requirements.md`: new REQ-F1.1; REQ-A1.3 `gh`-degradation clause; REQ-C1.2
  contradiction-channel clause.
- `test-spec.md`: new REQ-F1.1 entry; REQ-A1.1 branch-first ordering; REQ-A1.3
  `gh`-failure case; REQ-C1.2 channel assertion.
- `tasks.md`: REQ-F1.1 folded into T1/T3/T6 Done-whens + citations; Task 8
  docs-target named.
- `kickoff-brief.md` §2: glossary marker-window corrected.
- `specs/_observations/opportunities.md`: performance degradation-point note.

Validator after lens-pass edits: `0 errors, 0 warnings`.

### Sign-off record

Class: meaning
Lens-pass: recorded above (this section), full-bundle fan-out, findings
dispositioned 2026-06-26.
Anchor: `3becb245d27bb7ad056b7b23bdf99a6fabc874dd` — computed as
`scripts/spec-anchor.sh specs/orchestration-concurrency`

## 9. Amendment log

(none yet)

