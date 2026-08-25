# Model Allocation — Kickoff Brief

## 1. Header

- **Spec:** `specs/model-allocation/` (format-version 2)
- **Spec commit at walkthrough start:** `9f1dc20f01db6e611a0bd4d0d53a2cffd7743775` (bundle authored in `9dda237`)
- **Walkthrough date:** 2026-08-24
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff=true`, `mark_spec_pr_ready_on_kickoff=true`, `kickoff_ready_ci_wait=10m` (no local overrides)
- **Working location:** branch `planwright/model-allocation/spec`, checked out in the worktree `.claude/worktrees/model-usage` — a naming drift from the D-37 `<spec>-spec` convention, already recorded as an observation by `/spec-draft` (`9f1dc20`); the branch lives here, so the walkthrough proceeds in place.

## 2. Goal & glossary

**Restatement.** Today planwright picks a model and effort only at fleet dispatch, only
per task type, and never revisits the choice. This spec makes selection universal and
effort-aware: one deterministic resolver at every launch point (fleet dispatch,
single-spec `/orchestrate`, `/execute-task` per-step sessions, `/offload`); starting
tier from configuration; execution evidence (step failure/retry, flailing, review
non-convergence, worker petition) re-resolves the tier at the next launch boundary,
both directions; every choice clamped by fleet-autonomy's account-global usage signal,
restriction ladder, and per-tier caps, consumed as unmodified contracts (shared-aware
by construction). Default-preserving: configure nothing, observe no change.

**Rules out:** LLM calls in the resolution path (a petition is a signal, not an
authority); changes to the upstream budget machinery; mid-session switching; currency
accounting; context engineering (future spec); an authored complexity field (deferred
behind an evidence gate).

**Assumes:** fleet-autonomy's machinery is present and authoritative; per-step
isolation makes launch boundaries frequent enough for adaptation to bite; the audit
trail is the only adaptation memory (the D-28 memoryless-derivation pattern).

**Glossary resolutions.**

- **Tier** — a joint **(model, effort) point on one ladder**: an escalation step may
  raise effort within a model before jumping model aliases. Operator-chosen over the
  model-alias-only reading of D-8's "fixed alias ladder", explicitly accepting the
  added scope. The ladder's exact total ordering is a design decision, resolved at the
  D-8 walk (section 4). *(Carried spec edits: pin the joint ladder in D-8; sweep
  REQ-A/REQ-C wording for consistency once the ordering is fixed.)*
- **Audit surface** — the existing `fleet-audit.sh` trail (the store rung state is
  already derived from); the spec adds readers and appenders, not a new store.
  Resolved from repo evidence and D-6's citation of fleet-autonomy D-28.
- **Unit**, **rung**, **flailing** — carry their established meanings (spec-format
  glossary; fleet-autonomy's restriction ladder and liveness classifier).

*Amended at the sign-off lens pass (2026-08-25): the carried tier-wording sweep was
executed (cluster F); the audit surface moved to a dedicated per-unit allocation
ledger with a sparse fleet-audit mirror (cluster C, D-6 amended) — the fleet-audit
resolution above records the walkthrough-time reading.*

Signed off: 2026-08-24

## 3. Requirements walkthrough

Walked per group at intent level (the operator authored the bundle the same day;
depth went to gaps, not re-teaching).

- **REQ-A (selection policy):** confirmed as written. Carried item: sweep "tier"
  wording once the joint ladder is pinned (section 2 edit list).
- **REQ-B (launch-point coverage):** confirmed. Recorded reading: attended authoring
  sessions (`/spec-draft`, `/spec-kickoff`) are the operator's own session and fall
  under REQ-B1.3's in-session inheritance — no fifth launch point is missing.
- **REQ-C (execution-time adaptation):** confirmed, with one resolution. **Event
  stacking:** multiple trigger events accumulated at one launch boundary stack
  cumulatively — one ladder step per event, each event with its own audit row — and
  the clamps plus the per-unit escalation cap bound the result. This is the literal
  reading of REQ-C1.2's "one tier per triggering event"; no spec edit.
- **REQ-D (budget integration):** confirmed as written.
- **REQ-E (configurability):** confirmed as written.
- **REQ-F (observability and feedback):** confirmed as written.

No requirement edits arose in this section; the consolidated edit list stands at the
two section-2 items (D-8 ladder pin, tier-wording sweep).

*Amended at the sign-off lens pass (2026-08-25, cluster E): the cumulative-stacking
resolution is refined — trigger events carry idempotency identity and stack per
distinct event class at a boundary (same-incident classes collapse), closing the
one-incident-multi-count hole the lens exposed. Infrastructure failures are excluded
from the trigger set (D-2 amended).*

Signed off: 2026-08-25

## 4. Design walkthrough

**Ledger.** D-1, D-2, D-3, D-4, D-5, D-6, D-7, D-9, D-10, D-11, D-12: **confirmed**,
rationale intact (D-3's "starting tier" now concretely the configured (model, effort)
pair; D-5's knob names pair `allocation_model_*` / `allocation_effort_*` mirroring the
fleet families; D-6's store pinned to the fleet-audit trail; D-12's deliberate
non-edge re-verified for section 6). **D-8: amended in place** (Draft-stage edit,
operator-decided):

- Tier pinned as a joint (model, effort) point; escalation follows the successor rule
  (raise effort one level until `high`, then raise the model one alias keeping effort
  `high`); events at one boundary stack cumulatively, one step and one audit row each.
- Petition de-escalation reverses the most recent unreversed escalation step
  (audit-derived); with none to reverse it steps below the starting tier by the
  mirror rule, floored at the ladder bottom — chosen over reversal-only because D-7's
  recorded rationale (capturing "the remaining steps are mechanical") is the spec's
  own ground for the petition existing; escalation events self-correct a wrong step
  down.
- "Cheaper than" comparisons use model-major, effort-minor cost order.
- Long-term shape decided on the operator's direct ask: pin the rule now, defer a
  configurable `allocation_ladder` knob behind a drain-loop evidence gate (new
  Deferred entry in `tasks.md`) — the same evidence-first graduation pattern as D-3,
  per the customization-boundary tilt.

**Mid-walk delta-scoped lens pass** (run inline — narrow delta; per
`kickoff-verification`): finding 1, the petition/D-7 rationale tension above —
**applied** (mirror-rule edit). Finding 2, escalation at the ladder top
(`fable-high`) has no successor — **declined as already-implied** by the rule's
`while m < fable` bound (a top-of-ladder event is a no-op with its audit row; Task
2's tests pin it). The Deferred bullet, changelog chronology, and citation structure
passed the validator (0 errors, 0 warnings after each edit); the validator checks
structure, not citation-content drift — content consistency was later swept by the
sign-off lens pass.

*Amended at the sign-off lens pass (2026-08-25): the ledger above records the
walkthrough-time state. The lens pass subsequently amended D-1, D-2, D-5, D-6, D-7,
D-8, D-9, D-10, D-11 and minted D-13 (opt-in defaults); the sign-off record (section
8) is authoritative for the final reconciled bundle. The ladder-top no-op declined
here as already-implied was given explicit D-8 wording and a REQ-C1.2 fixture by the
revision.*

Signed off: 2026-08-25

## 5. Verification approach

**Coverage mix** (cited from `test-spec.md`; tallies derivable there): predominantly
`[test]` — deterministic shell suites under `tests/`, the right fit for a
determinism-floor spec; REQ-B1.1 is `[test + manual]`; REQ-B1.3 and REQ-D1.1 are
`[design-level]`.

**Ownership.** `[test]` entries run in CI on every PR via `mise run check` (whose task
list includes `test` → `scripts/run-tests.sh`), verified against `ci.yml` and
`mise.toml` during the walk. The single `[manual]` component (skill-prose launch
paths) is owned by Task 6's review as a recorded manual pass. `[design-level]` entries
are verified at task review (doc existence plus the doc-link guard for B1.3; absence
of upstream contract edits for D1.1). The named guards (`check-options-reference.sh`,
`check-doc-links.sh`) exist and run.

**Dead paths:** none — every named verification mechanism exists and runs.

**Edits applied (operator-approved):** two gap-fills flowing from the D-8 amendment —
REQ-C1.2's entry names the ladder-top no-op fixture; REQ-C1.3's entry names the
never-escalated below-starting mirror-rule fixture. Fixture wording only; no REQ
minted, no meaning altered. Validator clean after the edits.

*Amended at the sign-off lens pass (2026-08-25): the test-spec was subsequently
revised in full (clusters G and I) — discriminating fixtures for the ladder hinges,
stacking counts, clamp conditionality and composition, petition lifecycle and races,
degraded mode, a captured golden baseline, named suite references, structural guards
in place of negative-universal assertions, and the REQ-C1.7 / REQ-F1.3 entries. The
gap-fills above are folded into that revision.*

Signed off: 2026-08-25

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; `scripts/spec-graph.sh`
render consulted during the walk — cite the render, figures derive from it).

- **Shape:** Task 1 → Task 2 → a four-wide parallel tier (Tasks 3, 4, 5, 6) → Task 7.
- **Effort-weighted critical path:** 8 days, two co-critical routes — 1→2→3→7 and
  1→2→6→7 (efforts from the task blocks).
- **Deliberate edges (do not "fix"):** Task 5's and Task 6's edges on Task 2 are
  D-12's sequencing edges, not technical dependencies — adaptation lands before
  breadth by the operator's recorded priority.
- **Deliberate non-edges:** Tasks 3, 4, 5, 6 are mutually independent; in particular
  5 and 6 do not wait for the petition (3).
- **Orchestration consequence:** after Task 2, up to four units run in parallel;
  co-critical 3 and 6 dispatch first under critical-path-first selection.

Signed off: 2026-08-25

## 7. Risk register

**Decision-domains gap check** (merged catalog via `resolve-catalog.sh
decision-domains`): nine of eleven domains untouched or decided in the bundle. Two
touched-but-undecided domains surfaced; one resolved into a decision (petition
lifecycle → D-7 single-consumption amendment, with the REQ-C1.3 fixture consequence;
delta lens on the edit: consistency checked, validator clean), one accepted as risk
row 5 below.

| # | Risk | Mitigation / early signal |
|---|---|---|
| 1 | Joint (model, effort) ladder widens Task 2's rule surface beyond the model-only reading (scope accepted by the operator at section 2). | Pinned successor rule, no new knob (D-8); deferred `allocation_ladder` keeps flexibility out until evidence. Early signal: Task 2 effort overrun / extra polish iterations. |
| 2 | Petition-down / event-up oscillation: mirror-rule de-escalation followed by failure-driven re-escalation could cycle a unit. | Launch-boundary-only re-resolution, the per-unit cap, and single-consumption petitions (each cycle costs the worker a fresh petition) bound it; audit rows make it visible. Early signal: alternating petition/escalation rows on one unit in the trail. |
| 3 | Inheritance-degraded surfaces: a backend that cannot set model/effort makes the policy inert there while looking covered. | REQ-B1.2 mandates an inheritance audit row, never silent. Early signal: a high inheritance-row rate at one surface. |
| 4 | Upstream contract drift: fleet-autonomy changes rung/cap/signal semantics under this spec's feet. | Contracts consumed only through documented interfaces (D-1; test-spec REQ-D1.1 fixtures). Early signal: integration fixture breakage on a fleet-autonomy bump. |
| 5 | Audit-trail growth (accepted, gap check — data-storage): per-launch appends multiply the shared trail's volume; derivation re-scans it. | Rows ride the trail's existing lifecycle unchanged; remedy owner is a fleet-autonomy retention amendment, never this spec (D-1 fence). Early signal: derivation scan cost / trail size growth in Task 2 tests or fleet operation. |

No open questions remain: every question raised during the walk was resolved into a
decision (sections 2, 3, 4, 5, 7) or stands above as an explicitly accepted risk.

*Amended at the sign-off lens pass (2026-08-25):* row 2's oscillation bound gains the
symmetric adjustment cap and single-consumption petitions (each cycle now costs a
fresh petition and cap budget); row 5 is rescoped by the store decision — the
authoritative allocation records live in the per-unit ledger (bounded scans, own
retention), the shared fleet-audit trail receives only sparse governance events, and
REQ-F1.3's ledger-size/derivation-latency instrument is the detector behind the
early signal, closing the no-instrument gap. The lens pass also surfaced that the
walkthrough's gap check under-read the concurrency domain; the reconciled bundle now
decides it (per-unit lock discipline, claim atomicity, accepted global-clamp TOCTOU
with the reactive backstop as hard stop — design cross-cutting concerns).

Signed off: 2026-08-25

## 8. Sign-off

**Terminal lens review (first activation — full bundle; Discovery-Rigor fan-out, one
read-only agent per canonical lens; altitude check run within the pass).**

Lens-coverage table (raw per-lens counts before cross-lens dedup):

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 27 | Two REQ-level contradictions (defaults-preservation; clamp model vs consumed contracts) plus rule-coverage gaps |
| Security | 30 | Petition path/atomicity/binding posture unpinned; audit read path unscreened; numeric knob validation absent |
| Error handling and failure modes | 42 | Fail-open/closed branches unspecified for trail, append, clamp inputs, petition IO, signal reader |
| Performance | 16 | Shared-trail write amplification, unbounded scans, no perf fixture, accepted risk had no instrument |
| Concurrency / state | 38 | No unit key or row identity in the pinned store; derive+append lock contract not adopted; petition TOCTOU |
| Naming, readability, structure | 23 | Tier-wording sweep unexecuted; cap/threshold name collision; normative rules buried in one D-8 paragraph |
| Documentation | 23 | Task 7 missed kickoff-amended mechanisms; three knobs had no options-reference owner; dangling Sources |
| Tests / verification | 50 | Discriminating fixtures missing (clamp order, successor hinge, stacking); golden-baseline gap; negative universals |
| Cross-file consistency | 21 | Tasks 2/3 described the pre-amendment design; REQ layer understated the amended rules |

**Altitude check (REQ-H1.3):** untriggered bundle — the pinned seed claims are a
capability/mechanism ask, no altitude assertion; the one capability-vs-style moment
was resolved and recorded in D-3. Not applicable, per proportionality.

**Validation:** three converging angles per the load-bearing claims — each lens agent
grounded its findings against the shipped scripts; independent lenses converged on
the same defects from different directions; the coordinator re-verified the four
load-bearing grounded claims directly (the six-field audit row, rung-conditional
downshift, signal-dependent cap activity with the reserved exemption, the command
column and its closed enum).

**Dispositions (operator-decided, clustered):** the raw findings (per the table
above) deduped to nine root-cause clusters plus a standalone bucket; every one
dispositioned:

1. **A — defaults-preservation (applied):** fully opt-in — `inherit` sentinel at
   non-fleet surfaces, `allocation_adaptation` master knob shipping off, audit rows
   exempt from the preservation claim, golden-baseline equivalence. D-13 minted.
2. **B — clamp model (applied):** rewritten to defer to upstream semantics
   (rung-conditional downshift, signal-dependent caps, reserved exemptions, withheld
   outcome at defer rungs); nearest-surviving-model effort-preserved cap clamping;
   fail-closed unreadable inputs; clamping never called de-escalation.
3. **C — audit-store fit (applied):** per-unit allocation ledger (pinned schema,
   per-unit lock, degraded mode) authoritative; sparse governance-event mirror into
   fleet-audit. D-6 amended.
4. **D — petition hardening (applied):** grammar bounds, contained regular-file path
   posture, temp-then-rename writes, atomic rename-claim consumption, unit/step
   binding, invalid-also-consumed; one symmetric per-unit adjustment cap bounds both
   directions. REQ-C1.7 minted.
5. **E — tier-rule coherence (applied):** movement path and cost order declared as
   deliberately distinct orderings; per-event-class stacking with idempotency keys
   (refines the §3 record); net-displacement cap with refunds; step-scope ledger
   marking; zero-history and stuck-state rules; the §4 "self-correct" wording
   corrected (re-raise, not retrace).
6. **F — normative-layer sync (applied):** tier sweep executed; tested-but-unstated
   rules lifted into REQ text; D-8 restructured one-rule-per-bullet; term
   disambiguations and renames; petition-policy enum defined; changelog completed.
7. **G — task/test traceability (applied):** Tasks 1–7 rewritten to the reconciled
   design; `allocation_command_*` with the closed enum joins the family; the three
   unowned knobs gained options-reference owners; the capability-contract column
   added to Task 6; the discriminating-fixture set added to the test spec.
8. **H — failure modes (applied):** degraded mode on an unhealthy ledger (launch at
   last recorded tier, adjustments suspended, surfaced); signal-reader error ≡
   unavailable with hold-no-claw-back; infra failures excluded from triggers;
   per-dimension capability handling; append-before-launch with keyed reconciliation;
   terminal states include crash-loop disable.
9. **I — performance (applied):** within-boundary memoization allowance; scale and
   latency fixtures; the REQ-F1.3 instrument; the write-amplification observation
   cited as a Source.
10. **Standalone bucket (applied):** Sources corrections (REQ-E1.7 relabeled as the
    reactive backstop; customization-overlay and backend-capability-contract entries
    added; observation and research entries wired into citations).
11. **Declined:** the `Status:`/`Last reviewed:` staleness family — both are bumped
    by this flow's flip step, pending at the time the lenses read the files; and the
    brief's own validator over-claim, corrected in place rather than in the bundle.

All spec edits from the dispositions are on disk; the validator passes (0 errors,
0 warnings) and the post-lens stale-reference sweep over the bundle and earlier brief
sections is complete (minted IDs REQ-C1.7, REQ-F1.3, D-13 referenced and covered; the
adjustment-cap rename swept; affected earlier sections carry amendment notes).

**Pre-flip verification:** repository lint over the brief and all four spec files
clean (`mise run lint:md`, plus `check:ledger`, `check:memory-links`, and the
repo-wide `check:specs` after merging origin/main into the branch); recorded claims
re-derived (section 6's effort-weighted critical path from the task blocks; the
domain tally from the resolved catalog; minted-ID coverage by mechanical grep; one
copied figure caught and replaced by a table citation). Validator re-run clean at
Ready under the merged (post-`eedad48`) validator; the anchor below is computed with
the merged anchor script so the freshness gate recomputes with the same
implementation.

**Sign-off (first activation).** All seven sections signed; the lens pass above fully
dispositioned; no inconsistency halt, no carried open question. Approved by the
operator 2026-08-25; Status flipped Draft→Ready and `Last reviewed:` bumped on all
four files.

Class: meaning
Lens-pass: the terminal lens review recorded in this section (coverage table,
validation statement, and clustered dispositions above)
Anchor: `371e1d46cafbddc33abe3bf902dc8e1dc1b4f54e` — computed as
`scripts/spec-anchor.sh specs/model-allocation`
