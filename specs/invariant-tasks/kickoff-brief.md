# Invariant Tasks — Kickoff Brief

## 1. Header

- **Spec:** `specs/invariant-tasks`
- **Spec commit at walkthrough start:** `7189f30` (feat(spec): draft specs/invariant-tasks bundle)
- **Walkthrough date:** 2026-07-14
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator (pre-flight):** `spec-validate` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`

## 2. Goal & glossary

**Restatement (confirmed by the human as written).** `tasks.md` today is two
things in one committed file: invariant task definitions and a committed
snapshot of execution state (section placement, `Status` / `Last activity` /
`Dispatch` annotations, the header's Active/Done values). Since
orchestration-concurrency D-1 the snapshot is officially a derived read-model
— the derivation engine is the truth — yet every state change still costs a
commit: section moves, annotation stamps, anchor churn, hook machinery, and
(operational evidence, Sources) shared-checkout index races that forced
`commit_on_state_move: false` on a two-tower deployment. This bundle takes
the graduation orchestration-concurrency deliberately deferred:
**format-version 2**, where the committed `tasks.md` holds only what cannot
be derived — task definition blocks in a single `## Tasks` section plus the
human-authored payload (Awaiting-input reference bullets, Deferred, Out of
scope) — and all execution state is derived from git/PR evidence, read
through an on-demand CLI render, never committed, never mirrored remotely.
The stored `Status:` header shrinks to the human declarations (Draft, Ready,
Retired, Superseded); Active and Done become derived facts. Machinery
version-keys off the bundle's `Format-version:` line; v1 bundles stay valid
and operable indefinitely; this repo's live bundles migrate via a one-shot
byte-stable script; Done/terminal bundles are never rewritten.

**Rules out:** any committed or remote-mirrored derived-status artifact
(D-6); moving the human-payload sections out of the committed file;
re-deciding derivation internals or evidence precedence; selection-policy
changes; rewriting Done/terminal bundles; auto-merge (carried invariant);
non-GitHub hosts.

**Assumes** (machinery survey, Sources): the derivation engine already
computes full per-task status without reading committed sections; the
committed placement layer has a single writer (`tasks-pr-sync.sh`) and two
placement readers (the selector and the gate evaluator); the fleet decision
queue already covers remote status visibility.

**Glossary (implicit terms surfaced):**

- *the render* — the derivation engine surfaced as a human-facing command
  (Task 3); the canonical execution-status read surface for v2 bundles.
- *parked* — a task held by human decision: a live Awaiting-input bullet, or
  listed in Deferred / Out of scope.
- *live bundle* — a non-Done, non-terminal bundle (Draft, Ready, or Active):
  the migration population. (Resolution below widened this from the drafted
  "Ready/Active".)
- *human-payload sections* — `## Awaiting input`, `## Deferred`,
  `## Out of scope`: content only a human (or a halting skill) can author.
- *pointer line* — the constant `**Execution:** derived — see the status
  render` header line (D-5); fixed vocabulary, never per-bundle prose.

**Resolutions recorded:**

1. Goal restatement confirmed as written (selector, 2026-07-14).
2. **Draft bundles join the migration population** (selector, 2026-07-14):
   REQ-D1.3's "live" widened from Ready/Active to Draft/Ready/Active — a
   Draft costs nothing to convert (validator only warns on Draft) and this
   prevents a v1 Draft graduating to Ready under v1 rules after the repo
   moved on. A Draft has no signed brief, so it takes no re-anchor entry.
   Edits applied: scope bullet + REQ-D1.3 (requirements.md), D-10
   (design.md), Task 6 deliverables (tasks.md). See the consolidated edit
   list (§3).

Signed off: 2026-07-14

## 3. Requirements walkthrough

**REQ-A — the invariant committed ledger.** Intent restated and confirmed:
v2 `tasks.md` = definitions + human payload; commits only for definition
changes; stored header restricted; IDs/fields/dependency contract unchanged.
Decision: REQ-A1.2 tightened to "derived execution-state changes" with an
explicit clause that D-3 parking/unparking writes are human-authored
payload, not execution state (the drafted absolute wording contradicted
D-3's committed Awaiting-input bullet).

**REQ-B — derived status as the read surface.** Clean. Resolved and
reported (not asked): the render runs on any bundle the derivation engine
handles, but the canonical-read-surface claim is v2-scoped per REQ-B1.3's
own wording. The Awaiting-input bullet is the single human override signal
in the derivation (REQ-B1.4), consistent with D-3.

**REQ-C — machinery reconciliation.** Verified during the walk: parking
commits and REQ-C1.6's churn-free anchor coexist because the anchor's
`tasks.md` contribution is the definition-only canonical extraction and
Awaiting-input bullets sit outside task blocks — a parking commit never
moves the anchor. Decision: REQ-C1.5 gained "and the static `Execution:`
pointer line present" — Task 2 and test-spec REQ-C1.5 already enforced the
pointer line; the REQ now names what its verification tests.

**REQ-D — migration & coexistence.** Widened to Drafts in §2 (resolution 2
there). Byte-stability argument checked: the canonical extraction sorts
blocks by task id, so the id-sorted section collapse cannot change the
digest while definition lines stay byte-identical.

**REQ-E — doctrine, skills, lineage.** Grounded by repo grep during the
walk: `/execute-task` writes only `Last activity` (its instructions say
"write no placement or `Status`"; `Status` annotations come from
`tasks-pr-sync`), so REQ-E1.2's per-skill enumeration is complete. No
edits.

**Consolidated spec-edit list (all applied in place, Draft bundle):**

1. Scope bullet + REQ-D1.3: migration population widened to
   Draft/Ready/Active; Draft takes the byte-stable transform, no re-anchor
   entry (kickoff §2). Files: `requirements.md`.
2. D-10: same widening, amendment annotation added. File: `design.md`.
3. Task 6 deliverables: "(Draft/Ready/Active) bundles migrated, each signed
   bundle with its expression-only re-anchor (a Draft has none)". File:
   `tasks.md`.
4. REQ-A1.2: "derived" qualifier + human-payload clause; cites D-3. File:
   `requirements.md`.
5. REQ-C1.5: pointer-line invariant added; cites D-5. File:
   `requirements.md`.
6. D-4 Done clause restated to engine semantics (see §4). File:
   `design.md`.

Signed off: 2026-07-14

## 4. Design walkthrough

Reconciled D-ID ledger, every decision accounted for:

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 (altitude) | Confirmed | Format-capability graduation; altitude record present, cited from the Goal; opt-in seam is the `Format-version:` declaration itself. |
| D-2 (v2 shape) | Confirmed | One `## Tasks` section + human-payload sections; five fields, stable IDs, dependency contract unchanged. |
| D-3 (parking bullets) | Confirmed | Reference bullets, block stays put; REQ-A1.2 edit (§3) aligned the requirement's letter to it. |
| D-4 (restricted stored status) | **Amended** | Inconsistency halt raised and resolved: the drafted Done clause ("all non-parked tasks derive Completed") contradicted the consumed derivation rules (`tasks-pr-sync.sh:421-424` — an awaiting-input task blocks Done) and the bundle's own Out-of-scope line. Human chose engine semantics; Done clause restated: every task derives Completed and no live Awaiting-input bullet remains. Amendment annotation on D-4. |
| D-5 (pointer line) | Confirmed | Fixed vocabulary defined by the meta-spec; now also cited from REQ-C1.5 (§3 edit). |
| D-6 (CLI render only) | Confirmed | No committed or remote-mirrored status artifact; fleet decision queue covers remote visibility. |
| D-7 (version-keyed machinery) | Confirmed | `Format-version:` selects behavior; v1 arms retire behind the Deferred gate. |
| D-8 (selector/gate re-sourcing) | Confirmed | The survey's two placement readers are exactly the re-sourced points. |
| D-9 (anchor untouched) | Confirmed | Churn-freedom falls out by construction; parking commits verified not to move the anchor (definition-only extraction, §3). |
| D-10 (migration) | **Amended** | Draft bundles joined the migration population (§2 resolution); annotation on D-10. |
| D-11 (completion-annotation supersession) | Confirmed | Supersession recorded at Task 8 per the ritual; output-hygiene text never edited retroactively. |

No unaccounted decisions; no design decision contradicts a walked
requirement after the D-4 amendment.

Signed off: 2026-07-14

## 5. Verification approach

**Coverage mix:** as stated in `test-spec.md`'s intro (cited, not copied):
machinery REQs (B/C/D) verify as `[test]` entries in the shell suite under
`tests/`, run by `mise run check` in CI; format and doctrine REQs (A,
E1.1) are `[design-level]` against the meta-spec text plus validator
fixtures; the entries for REQ-B1.3, REQ-D1.3, and REQ-E1.2 carry a
`[manual]` arm.

**Ownership:** GitHub CI runs every `[test]` entry via `mise run check`
(`tests/*.sh`, bash-3.2 floor, mise.toml `[tasks.test]`). The human sweeps
the three `[manual]` arms at their named task PRs: REQ-B1.3 (read a live
v2 bundle's status via the render only), REQ-D1.3 (migration-PR diff
review: only live bundles changed), REQ-E1.2 (end-to-end toy-bundle pass:
draft → dispatch → park → complete, no committed state writes).

**Dead-path check:** none found. Grounded during the walk:
`scripts/check-options-reference.sh` exists and is wired (mise.toml:82);
the per-script fixture-suite idiom the entries assume exists under
`tests/`; every `[test]` path is runnable in existing CI. The `[Gherkin]`
tag is unused, consistent with the intro's mix statement.

Signed off: 2026-07-14

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; render via
`scripts/spec-graph.sh`): T1 → {T2, T3} in parallel; then T4 (1,2), T5
(1,3), T7 (1,2,3); then T8 (1,4); T6 (1,2,4,5) last.

**Effort-weighted critical path:** T1 → T2 → T4 → T6 (5 days of the
bundle's total; per-task efforts cited from `tasks.md`). Widest
parallelism: three units (T4/T5/T7) once T2 and T3 land.

**Deliberate non-edges (recorded so nobody "fixes" them later):**

1. T3 and T5 do not depend on validator T2: their v2 fixtures live under
   `tests/`, not `specs/`, so they are not validator-protected content.
   The tasks.md guard-first note covers committed spec bundles — T4, T6,
   and T7 all edge to T2.
2. T7 does not depend on T5/T6: skill instructions may describe
   render-reads before the selector script is v2-ready; harmless because
   nothing dispatches a v2 bundle until T6 migrates one, and T6 requires
   T5.
3. T8 does not depend on T6: docs may describe the v2 model before this
   repo's own bundles migrate.

Signed off: 2026-07-14

## 7. Risk register

Decision-domains gap check: walked all eleven core-catalog domains via the
merged catalog (`resolve-catalog.sh decision-domains`; no overlay
additions). Domains the spec touches are decided (data-storage D-2/D-10,
api-surface via the versioning ritual + row 7's resolution,
deploy-migration D-10, dependency-adoption and versioning-scheme D-1 /
cross-cutting); the concurrency and observability domains produced rows 4
and 5.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Spec-belief bugs encoded into fixtures (D-45 class) — the walk caught one in D-4's Done clause. | Task 3/4 fixtures assert against the real engine's behavior, not spec prose. Signal: fixture-vs-engine disagreement. |
| 2 | Dual-arm (v1+v2) maintenance burden in every touched script. | Both-arm fixtures required (REQ-D1.1); retirement staged behind the Deferred gate. Signal: a script change landing with only one arm tested. |
| 3 | GitHub readers misread a finished v2 bundle ("Ready" forever). | D-5 pointer line. Signal: "did this ever run?" questions. |
| 4 | **Accepted risk** (concurrency domain): parking still commits — concurrent parks on a shared checkout can race the index. Accepted: human-gated and rare vs the per-dispatch churn removed. | Signal: index-lock failures on park. |
| 5 | **Accepted risk** (observability domain): no remote execution-status surface. Accepted per D-6: render + fleet decision queue cover it. | Signal: adopter requests for a PR-body mirror. |
| 6 | Migration byte-stability on odd v1 formatting. | Digest-assert fixtures (REQ-D1.2) + human diff review of the migration PR (REQ-D1.3 manual arm). Signal: extraction-digest mismatch in fixtures. |
| 7 | Render-output contract creep (scripts parsing the human text). **Resolved:** the derivation engine is the machine surface; the render is human-facing, non-contractual (D-6 sentence added at kickoff; a machine-readable mode stays an additive follow-up). | Signal: an external script parsing render text appears. |

No open questions remain: rows 4 and 5 are explicit accepted risks; row 7
was resolved as a D-6 clarification.

Rows appended at the sign-off lens pass (2026-07-14):

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 8 | **Documented limitation** (REQ-B1.4): a parking bullet committed on an unmerged worker branch is invisible to the main-view derivation until it lands; the task derives in-progress from branch evidence meanwhile (no re-dispatch — verified — but attention latency). | Signal: a parked task going unnoticed until its PR lands; fleet/notification layer owns interim attention. |
| 9 | Migrating a bundle while its execution is in flight re-anchors it; a dispatch racing the migration merge fails closed at the freshness gate (safe but disruptive). | Run Task 6's live-bundle migration in a quiet window. Signal: freshness-gate halts immediately after the migration PR merges. |
| 10 | Per-invocation derivation cost accepted with no cache (D-12). | Revisit signals recorded in D-12: render latency complaints, gh secondary-rate-limit hits. |

Signed off: 2026-07-14

## 8. Sign-off

**Mode and scope:** first activation; Discovery-Rigor lens pass over the
full bundle, fanned out to nine read-only sub-agents (one per canonical
lens) per the discovery-rigor doc, with the shared validator output (0
errors, 0 warnings pre-pass) passed to each. Coordinator merged and
deduped 96 raw findings into 21 dispositions, ran the mandatory
self-critique pass (added the migration-timing row), and validated per
validation-rigor: sub-agents grounded claims in the actual scripts and
sibling specs; the coordinator independently re-verified every
load-bearing claim (STATUS_AWK location, drain-gates section read,
parked blocks in real bundles, kickoff-lifecycle deferral text,
orchestration-concurrency gate text, orchestrate-state fail-closed exits)
and ran the adversarial bi-directional re-validation over keep and decline
sets.

**Kickoff-specific altitude check (pass):** triggered bundle (two pinned
we-keep-doing-X-manually seed claims in `## Sources`); altitude D-ID D-1
exists, is cited from the Goal, and the task decomposition matches the
claimed format-capability altitude (Task 1 defines the capability; Tasks
2–6 are core-script mechanism; no doctrine-claim-with-only-mechanism-tasks
mismatch).

**Lens-coverage table (canonical):**

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 12 | ported-derivation premise, Deferred/OoS task gap, stored-status/zero-task edges |
| Security | 10 | posture unbound to REQs/fixtures; bullet = new authoritative parse surface |
| Error handling and failure modes | 20 | migration atomicity/idempotency; fail-open version-keying; transient-remote mode |
| Performance | 6 | deleted snapshot was the consumed spec's read-model cache; caching decision reopened |
| Concurrency / state | 11 | branch-parked visibility; orphan-reconcile home; reopen vs lingering evidence |
| Naming, readability, structure | 8 | render-vs-engine read-surface contradiction; term drift; Task 4 title |
| Documentation | 5 | four stale doc surfaces unnamed; missing changelog entry |
| Tests / verification | 15 | reopen, pointer vocabulary, per-token, run-twice, bundle-level Done unverified |
| Cross-file consistency | 9 | kickoff-edit ripples; consumed-contract characterizations; second normative home |

**Dispositions (all resolved with the human, six clusters, 2026-07-14):**
18 of 21 merged findings **applied** as spec edits — new REQ-B1.5,
REQ-B1.6, REQ-C1.8, REQ-C1.9; D-3 generalized to all human-payload
sections; D-4 stored-status gating + zero-task rule; D-6 ported-derivation
scope; D-7 fail-closed version-keying; D-10 idempotency/atomicity +
parked-block conversion; D-11 second normative home; new D-12
(accept-no-cache); REQ-E1.2 read-surface split; Goal/Sources
consumed-contract corrections (Maximal gate recorded satisfied, argued in
its own terms; kickoff-lifecycle deferral scoped to its Active/Done half);
task and test-spec strengthening throughout; terminology unified. 3
findings **recorded** as register rows / documented limitations (rows
8–10). 3 findings **declined** with rationale: the "live" adjective
overload (idiomatic, context-disambiguated); REQ-D1.3's manual arm as
redundant (deliberate human second key); the claimed Ready-reclassification
contradiction (D-4 records the re-modeling explicitly). No finding left
undispositioned.

**Consolidated lens-pass edit list:** requirements.md (Goal, REQ-B1.4–B1.6,
REQ-C1.5, REQ-C1.8–C1.9, REQ-D1.2, REQ-E group title, REQ-E1.2, Changelog,
Sources); design.md (D-3, D-4, D-6, D-7, D-10, D-11, D-12, cross-cutting
security note); tasks.md (all eight task blocks); test-spec.md (REQ-A1.2,
A1.3, B1.1–B1.6, C1.4–C1.6, new C1.8–C1.9, D1.2, E1.3, E1.4).

**Status flip:** Draft→Ready on all four spec files, `Last reviewed:`
2026-07-14; post-flip validation under errors-block enforcement:
`spec-validate` — 0 errors, 0 warnings.

**Sign-off record (first activation, 2026-07-14):**

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-07-14.
Anchor: `a8cfcf9a86febcd22d946098548e0953aaab4c93` — computed as
`scripts/spec-anchor.sh specs/invariant-tasks`

## Amendment log

### Amendment 1 — self-review delta re-sign-off (2026-07-14)

**Scope:** the gauntlet's `/self-review` pass over the spec branch: four
grouped read-only reviewers covering all nine canonical lenses over the
post-sign-off final state; 42 raw findings merged to 16. Project tooling:
`mise run check` — `lint:md` failed (MD001, test-spec heading structure),
all other tasks green including `check:specs` (0/0); suite fully green
after the fix.

**Dispositions:** 1 Auto-applicable (the MD001 heading fix; tool-grounded,
action commit); 10 applied pending sign-off, one commit each on the spec PR
(PS-1 Done universe for deferred/OoS-parked tasks; PS-2 fail-closed
version-keying coverage; PS-3 sanitize scope; PS-4 failure-signal contract;
PS-5 migration re-anchor atomic unit; PS-6 halting-skill authorship +
orphan-park target; PS-7 parked-ness unification; PS-8 D-10/guard-note
alignment; PS-9 D-12 fleet consumer; PS-10 verification alignment); 3
declined with rationale (observation-fragment file mode — git stores
100644 regardless; the "two-tower" deployment mention — acceptable
shape-of-risk detail per security-posture, watch item; D-12 resting
task-cited only — the citation convention binds REQs, not D-IDs, and
Task 3 cites it); 2 recorded as the brief corrections below.

**Brief corrections** (sections above are append-only; recorded here):

- §4 ledger: D-12, added at the sign-off lens pass, was absent from the
  table — disposition **Confirmed**; the ledger's every-decision claim now
  reads D-1–D-12.
- §8 tally: the 3 declined findings sat outside the 21 clustered
  dispositions (screened during validation); the sign-off's totals were 24
  merged findings — 18 applied, 3 register rows, 3 declined.
- §3 stale prose: "the Awaiting-input bullet is the single human override
  signal" predates the D-3 generalization (any reference bullet now
  overrides); "the render runs on any bundle" predates REQ-B1.6's
  stored-status gating.
- The kickoff Changelog entry's walkthrough-vs-lens-pass attribution was
  corrected in place (D-6 machine-surface = walkthrough §7; C1.5 bullet
  integrity = lens pass; REQ-B1.4/REQ-D1.2 named in the lens-pass list).

Class: meaning (additions rule, REQ-A3.3 — the delta adds requirement
sentences and fixtures)
Lens-pass: this amendment's self-review pass, recorded above; findings
dispositioned 2026-07-14.
Anchor: `770aa876f32cb70d90298af66747793ace63b62e` — computed as
`scripts/spec-anchor.sh specs/invariant-tasks`

### Amendment 2 — panel delta re-sign-off (2026-07-14)

**Scope:** the gauntlet's `/panel-pairing` pass (backend: gemini 0.45.2,
per `panel-backends`; repo-class solo; Agent-resolvable bucket unavailable
— no Active spec pre-merge). Iteration 1 of 15: seven backend findings,
validated per the three-pass rigor; five confirmed, two refuted. No
Auto-applicable items, so the loop stopped at Human attention required;
the human directed **apply all five**, which are therefore
human-approved (not pending sign-off):

1. Reference-bullet cross-section exclusivity: a task is parked in one
   section at a time; validator enforces it (REQ-C1.5, D-3, test-spec).
2. The unparseable-`Format-version:` case errors at every status — carved
   out of Task 2's Draft-warns arm (REQ-C1.8 consistency).
3. Skill reconciliation version-keyed; v1 bundles keep today's skill
   behavior (REQ-E1.2, Task 7).
4. The migration's re-anchor entry cites a dated changelog line the
   migration appends; idempotency covers both artifacts (REQ-D1.2, D-10,
   Task 6, test-spec D1.2).
5. D-5's pointer-line text pinned as canonical ("e.g." dropped).

**Declined with rationale:** (a) a Task 5→Task 4 dependency — the
corruption precondition (a live v2 bundle before both land) cannot occur:
in-repo v2 bundles appear only via Task 6, which depends on both, and
adopter releases ship all scripts atomically; recorded as a deliberate
non-edge alongside §6's list. (b) zero-task derived state undefined —
REQ-B1.6 defines it (never Done, "no tasks" report, stored value renders).

**Tooling:** `mise run check` on the pre-panel head — every task green
except `[test]`, whose failure was diagnosed as machine-local (a global
`~/.gitignore` entry shadows `specs/_observations/` inside the obs-suite
fixture repos, so their `git add` stages nothing; verified via
`git check-ignore` in a fresh fixture and unrelated to this branch's
markdown-only diff; recorded as observation
`2026-07-14-global-gitignore-shadows-obs`). GitHub CI on the pushed head
is the arbiter. Validator 0/0 and `lint:md` 0 errors after the panel
edits.

Class: meaning (additions rule, REQ-A3.3)
Lens-pass: the panel pass plus this session's three-pass validation,
recorded above; findings dispositioned by the human 2026-07-14.
Anchor: `b4d0819fcf23112545bff18d42bdce24f234ce73` — computed as
`scripts/spec-anchor.sh specs/invariant-tasks`

### Amendment 3 — expression-only self-re-anchor (2026-07-15, PR #187 ledger reconcile)

Machine-written entry per REQ-F1.10's expression-only lane (the one anchor
entry an execution skill may write).

**Trigger:** the ledger reconcile `chore(spec): reconcile invariant-tasks
ledger to merged reality` (PR #187, commit `035b858`) flipped
`**Status:** Ready` → `**Status:** Active` on all four bundle files (Task 1
merged via PR #181 on 2026-07-15; Tasks 2/3 dispatched with work in flight)
and moved the Task 1 block from `## Forward plan` to `## Completed` with
the canonical v1 completion annotation. No requirement, design decision,
task definition, or test semantics changed (REQ-A3.3 expression-only):
lifecycle status and section placement only.

**Why the anchor moved:** solely the known Status-header gap —
`scripts/spec-anchor.sh` hashes requirements.md, design.md, and
test-spec.md whole, so the `**Status:**` header rides in the anchor (the
documented, human-deferred exclusion; see the 2026-06-29
anchor-blocker(kickoff-lifecycle) entry in
`specs/_observations/opportunities.md`). Verified by isolation: the
pre-#187 tree recomputes to Amendment 2's `b4d0819f…` exactly (nothing
else drifted since the last sign-off), and the same tree with only the
Status flips applied recomputes to `11e58813…`, the current anchor — the
Task 1 placement move (and its `Status:` completion annotation) is
anchor-neutral via the canonical tasks.md extraction, as designed.

No dated `## Changelog` entry accompanies this re-anchor: the trigger is
an orchestration/lifecycle reconcile, not an in-place spec-content fix
(the mandatory-Changelog rule attaches to expression-only *edits*); the
change record this entry cites is PR #187's commit, per the
orchestrate-state-move re-anchor precedent in
`specs/bootstrap/kickoff-brief.md`.

Class: expression-only
Anchor: `11e588133154cce23c3132126156f8c8ab15ecbf` — computed as
`scripts/spec-anchor.sh specs/invariant-tasks`

### Amendment 4 — expression-only self-re-anchor (2026-07-15, Task 8 completion-annotation supersession)

Machine-written entry per REQ-F1.10's expression-only lane (the one anchor
entry an execution skill may write).

**Trigger:** Task 8 (docs, config, and supersessions) recorded the D-11
completion-annotation supersession as the dated 2026-07-15 `## Changelog`
entry in `requirements.md` (citing D-11, REQ-C1.7). Recording it is a
gap-fill consistent with the accepted decisions — D-11 was signed off at
kickoff and REQ-C1.7 mandates recording the supersession via the ritual
(D-ID plus dated changelog entry) — so it is expression-only per REQ-A3.3:
no requirement, design decision, task definition, or test semantics changed,
only the changelog gained the supersession record the ritual requires.

**Why the anchor moved:** the changelog entry adds content to
`requirements.md`, which `scripts/spec-anchor.sh` hashes whole; `design.md`,
`test-spec.md`, and the canonical `tasks.md` definition content are unchanged
(Task 8's Last-activity annotation is anchor-excluded). Verified by
isolation: immediately before this changelog edit the tree recomputed to
Amendment 3's `11e58813…` (the Task 8 Last-activity stamp left it unchanged,
as designed), and adding only the changelog entry yields `0091eb69…`.

**Cites the changelog line:** the 2026-07-15 `## Changelog` entry in
`requirements.md` ("Completion-annotation supersession recorded (Task 8,
D-11, REQ-C1.7)").

Class: expression-only
Anchor: `0091eb6937059dc3f901a6d94adb58a7c1e8287e` — computed as
`scripts/spec-anchor.sh specs/invariant-tasks`

### Amendment 5 — expression-only self-re-anchor (2026-07-15, format-version 2 migration)

Machine-written entry per REQ-F1.10's expression-only lane, recorded by
`scripts/migrate-format-version.sh` (invariant-tasks D-10, REQ-D1.2).

**Trigger:** the one-shot v1→v2 migration converted this bundle to
format-version 2: placement sections collapsed into `## Tasks`, state
annotation bullets stripped, any parked task blocks converted to reference
bullets, the stored header restricted to the human-gated set, the
`**Execution:**` pointer line added, and `Format-version:` bumped on all
four files. Task definition lines are byte-for-byte unchanged (the
canonical `tasks.md` extraction digest was verified equal before
writing), so no requirement, design decision, task definition, or test
semantics changed — the required re-anchor rides the migration as
expression-only (REQ-A3.3, REQ-D1.2).

**Cites the changelog line:** the 2026-07-15 `## Changelog` entry in
`requirements.md` ("Migrated to format-version 2").

Class: expression-only
Anchor: `aca926877d45b9bf91ddb6b02db75cef0d938fcb` — computed as
`scripts/spec-anchor.sh specs/invariant-tasks`
