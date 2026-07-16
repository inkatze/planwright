# Inception — Kickoff Brief

## 1. Header

- **Spec path:** `specs/inception`
- **Spec commit at walkthrough start:** `c551736` (feat(spec): draft specs/inception bundle)
- **Walkthrough date(s):** 2026-07-10 —
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh specs/inception` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local
  overrides)
- **Rule docs resolved:** spec-format, discovery-rigor, validation-rigor, security-posture,
  decision-domains, interaction-style — all from this worktree's `doctrine/`
- **Working location:** spec worktree `.claude/worktrees/inception-spec`, branch
  `planwright/inception/spec` (9 commits behind `origin/main` at walkthrough start; untracked
  `research/` directory is deliberate operator-side material per the spec's Sources)
- **Pre-walkthrough research:** operator requested a state-of-the-art re-check before the walk;
  three commissioned sweeps (tooling landscape and D-1 adversarial check; persona-panel patterns;
  validation/collaboration seams) recorded operator-side under `research/sota-*.md`, findings
  folded into the walkthrough sections below as F1–F16.

## 2. Goal & glossary

**Restatement (confirmed by the operator):** `/inception` is the pipeline stage for ideas that do
not yet have a home. It takes a fuzzy, product-level, multi-discipline idea and produces a
durable, validated orientation — not a spec: the inception bundle (brief, discipline/stakeholder
map, assumption register, decision backlog, validation plan) inside a venture git repo the skill
creates and wraps so non-engineers can operate it. Its distinctive core is the discipline-persona
table: small, parallel, evidence-grounded seats compiled from task-framing cards, synthesized
once, challenged once, with structural honesty about which calls only a human can make.
Validation work runs deliberately light (PR-less, human-accepted, register-linked). A four-outcome
human gate governs progress; graduation emits a seed package to `/spec-draft` — never a spec,
never auto-chained. Rules out: inventing the pitch, deciding human-authority calls, non-git
truth, symmetric sync, identity personas. Assumes: single operator, Claude Code primitives only,
operator holds the decision on everything irreversible.

**Implicit terms surfaced:** venture, track, seat/bench, frame, operator vs stakeholder vs gate
decider, minimum core, rung. All but two are defined by the D-IDs; the two ambiguities were
resolved:

1. **Altitude boundary (home-repo ideas).** Resolution: operator's choice — the out-of-scope
   line means "not a replacement", not a ban; a home-repo idea may opt into a venture; routing
   heuristics stay recommend-only both directions. Applied as a Scope clarification in
   `requirements.md`.
2. **Track identity.** "Track" was load-bearing (Goal, REQ-E, REQ-F1.1, REQ-F1.3) but
   structurally undefined. Resolution: REQ-C1.11 added — optional track labels on assumptions,
   decisions, and plan tasks; single-track ventures need none; gate records may carry per-track
   outcomes; partial graduation keys on labels; grammar lives in the inception-format doctrine.
   Test-spec entry added.

Signed off: 2026-07-10

## 3. Requirements walkthrough

**Scope:** all 11 REQ groups (A–J, P) restated; the 2026-07-10 SOTA re-check adopt/adapt findings
folded per the operator's clustered dispositions (all "Apply all", 2026-07-13). Consolidated REQ
edits applied in place.

**Per-group outcomes:**

- Groups A, B, D, E, F, H, J — confirmed as drafted; no requirements-text change beyond the probe
  edits below.
- Group C — register fields sharpened: REQ-C1.3 (believe/verify/measure/right-if skeleton,
  evidence-ladder grade, fail-condition thresholds, synthetic-grade + Graduate exclusion),
  REQ-C1.4 (MADR deciders + consequences, merge-as-ratification), REQ-C1.5 (time/cost cap +
  single-limiting-constraint tie-break), REQ-C1.7 (reader version-gating fail-closed +
  additive-within-major evolution).
- Group I — REQ-I1.4 now names the evidence ladder, fail-condition thresholds, and the synthetic
  grade the register cites; REQ-I1.3 (non-code lenses) and the seam-reuse domain unchanged.
- Group P — persona cluster folded: REQ-P1.1 (frame-specific mandate, ordered frameworks, named
  knowledge-sources, blind spots, conflict/deference, stance axis), P1.2 (out-of-scope line), P1.3
  (anonymize + shuffle before synthesis), P1.4 (persona-free synthesis + challenge), P1.5 (typed
  triggers + typed human powers + per-seat independence), P1.6 (stake-scored triage + per-seat
  model default), P1.8 (zero-seat collapse), P1.9 (convergence demotion).

**Probe resolutions (operator calls, 2026-07-13):**

1. Kill-date blindness (REQ-C1.6 / E1.3 / J1.7): accepted v1 limitation; the no-arg portfolio
   surfaces tripped/approaching dates on invocation (no daemon in v1). → risk R1.
2. Zero-seat vs unstaffed auto-file (REQ-B1.5 ↔ P1.8): collapse to a single "personas waived
   (zero-seat); N unstaffed" row. → REQ-P1.8 edit.
3. Export staleness on the local rung (REQ-G1.1 ↔ A1.9): scaffold a pre-commit export-regen step
   on every rung. → REQ-A1.9 / G1.1 edits, D-9. → risk R2.
4. Ephemeral home (REQ-A1.4 / A1.5 / H1.1): proceed session-only-warned per the ladder floor,
   never a silent refusal. → REQ-A1.5 clarifying clause.

Signed off: 2026-07-13

## 4. Design walkthrough

Every D-ID accounted for; all confirmed with rationale intact except the following amended (SOTA
adopt/adapt, operator "Apply all"):

- **D-1** — claim tightened: Product Forge and GLIDR AI named as nearest misses; the uncomposed
  claim scoped to an evidence-graded register + decision backlog + thresholded validation plan at
  venture scope, git-native. Additive-within-major evolution + reader version-gating added.
- **D-2** — Ringelmann scaling-law citation (arXiv:2606.02646); anonymize + order-shuffle before
  synthesis/challenge; persona-free synthesis + challenge; convergence marks demoted to a weak,
  claim-type-annotated, outlier-named signal; Forward-log known-tension note (one-amendment cap vs
  multi-round critic gains; confidence-gated escalation is the evidenced later shape).
- **D-3** — card schema gains frame-specific mandate, ordered framework sequence, named
  knowledge-sources, out-of-scope line, blind spots, conflict/deference rules, optional stance axis.
- **D-4 / D-6** — out-of-scope negative line; typed escalation-trigger taxonomy; typed human powers
  (disregard/override/reverse/halt) at Gate 2; per-seat independence.
- **D-7** — stake/reversibility-scored seat-count triage (SHOULD, where the signal is cheap);
  per-seat model override where the backend advertises it, lost decorrelation reported (softened
  from SHALL/by-default in the sign-off lens pass, per the scope finding).
- **D-20** (new) — records the product/doctrine altitude (upstream of `/spec-draft`,
  doctrine-first decomposition), cited from the Goal; the altitude-record insurance from the lens
  pass.
- **D-8** — atomic registry writes (write-temp-then-rename); scan-rebuild remains recovery (R7).
- **D-9** — regeneration wired as a scaffolded pre-commit step on every rung.
- **D-10** — Notion unresolved-only harvest + no resolve-API (repo triage ledger is the only
  record) + pinned API version + Markdown Content API; Google Docs re-ranked (drive.file, no CASA —
  strong v2, still deferred); Outline added to deferred; Coda double-justified.
- **D-11** — Cowork protocol imported from venture root `CLAUDE.md` (filename-contract hedge);
  egress-blocked push/pull degrades gracefully; advisory + D-12 validator is the enforcement.
- **D-14** — gate records are structured machine-readable entries
  (outcome/date/decider/evidence/thresholds/rationale), not prose.
- **D-15** — seed stays format-clean enough to also emit a Spec Kit `/specify` input (interop
  constraint, no v1 work).

No design decision contradicts a walked requirement (verified in the sign-off lens pass).

Signed off: 2026-07-13

## 5. Verification approach

Coverage mix unchanged (fixture `[test]` + `[manual]` dogfood + `[design-level]` + `[Gherkin]`); no
dead paths introduced. New fixtures/assertions added across REQ-A1.6 (atomic-write concurrency),
A1.9 (pre-commit regen every rung), C1.3 (ladder grade + synthetic exclusion), C1.4 (MADR fields),
C1.5 (caps + constraint tie-break), C1.7 (unsupported-version fail-closed), E1.1 (synthetic blocks
desirability Graduate), E1.5 (machine-readable gate record), P1.1 (new card fields +
frame-specific-question lint), P1.2 (out-of-scope line), P1.3 (anonymized/shuffled synthesis
input), P1.4 (persona-free steps), P1.5 (typed triggers + human powers), P1.8 (zero-seat collapse),
P1.9 (claim-type-annotated convergence). Ownership: `[test]` under `mise run check` CI; `[manual]`
swept by the continuous dogfood (Task 17) + Cowork validation (Task 14).

Signed off: 2026-07-13

## 6. Task graph

Dependency graph unchanged (the `Dependencies:` lines are authoritative). Critical path
Task 1 → 2 → 7 → {9, 10, 11}; walking-skeleton arc (1 → 2 → 7 → 8 + Task 12 stub) ships first;
guard infra (1, 2, 3) leads; Task 17 dogfood runs continuously. No SOTA edit adds a task; all
extend existing deliverables (Task 1 grammar + version rules, Task 2 fixtures + pre-commit scaffold,
Task 3 evidence doctrine, Tasks 4/5 card fields, Task 8 atomic writes, Task 9 fan-out mechanics,
Task 11 gate record, Task 12 pre-commit regen, Task 13 Notion, Task 14 Cowork; Deferred gains
Outline). New coupling (not a new dependency): Task 2's hygiene scaffold emits a pre-commit hook
that invokes the renderer (Task 2 ships the stub, Task 12 replaces it). Deliberate non-edges
(parallel cards, independent seats) preserved.

Signed off: 2026-07-13

## 7. Risk register

**Decision-domains gap check:** walked all 11 catalog domains (`resolve-catalog.sh
decision-domains`). Decided/covered: data-storage (D-5/D-8), caching (n/a — regen-on-commit),
queues-async (D-7), api-surface (D-10/D-15/C1.7), auth (G1.7/A1.9/security-posture), secrets-config
(A1.3/I1.6/G1.7), observability (D-8/J1.8), dependency-adoption (D-9/D-10 + the seam-reuse domain
the spec adds), versioning-scheme (C1.7). Two touched-but-undecided domains were decided this
session: concurrency (R7) and deploy-migration (R8).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | Kill-date blindness (no daemon) | Portfolio surfaces tripped/approaching dates on invocation; accepted v1 limitation |
| R2 | Export staleness on out-of-session edits | Pre-commit export-regen scaffold + CI where remote; residual on rungs lacking the hook |
| R3 | Convergence-mark over-trust (correlated errors) | Claim-type annotation, outlier naming, never-as-probability; grounding outranks vote count (D-2/P1.9) |
| R4 | Synthetic/persona-panel evidence over-trust | Named low grade, excluded from a desirability Graduate threshold (C1.3/E1.1/I1.4) |
| R5 | IP / AI-arch card + platform-claim staleness | Rot metadata + build-time re-verification (design cross-cutting) |
| R6 | Multi-agent cost blowup | Gate 1 discloses seats × backend × cost; small default + bench; stake-scored triage (P1.6) |
| R7 | Concurrent-session registry write race | Atomic write-temp-then-rename prevents torn writes; a rare lost-update self-heals via the ventures_root scan-rebuild (REQ-A1.6/D-8) — resolved this session |
| R8 | Inception-format version skew (bundles outlive plugin) | Reader version-gating fail-closed + additive-within-major evolution; migration transform deferred to first breaking bump (REQ-C1.7) — resolved this session |

Open questions: none — all resolved to decisions or accepted risks.

Signed off: 2026-07-13

## 8. Sign-off

**Mode / scope:** first activation, resumed at §3; full-bundle walkthrough; the consolidated
SOTA-fold (~60 edits) applied in place, then a full-bundle sign-off lens pass with its findings
applied (~40 further edits).

**Lens review pass.** Parallel Discovery-Rigor fan-out — five read-only lens sub-agents (cross-file
consistency, coverage completeness, claims/data-hygiene, failure-modes/structure, altitude/scope) —
plus an independent gemini panel pass (different model family). The gemini pass caught three
logical contradictions the native fan-out missed: anonymized-synthesis attribution (impossible for
a blind writer to re-attach), persona-free-challenger-vs-"declares-standing", and "desirability"
not being one of the four risk tags. All three were resolved (orchestrator-held seat↔label map;
independence moved to the card; desirability = value + usability risk).

Lens-coverage table:

| Lens | Findings | Disposition |
| --- | --- | --- |
| Correctness / logic / edge cases | 1 | Applied — atomic-write lost-update reworded to accept scan-rebuild recovery |
| Security / data-hygiene | 0 | Clean — no secrets, hostnames, or sensitive detail introduced |
| Error handling / failure modes | 4 | Applied — regen stage-and-warn; model-degrade → REQ-H1.5; version-gate exit; Cowork advisory clarified |
| Performance | n/a | Multi-agent cost via Gate-1 disclosure + bench; no new hot path |
| Concurrency / state | 1 | Applied — registry lost-update (same root as correctness) |
| Naming / readability / structure | 1 | Applied — D-2 "Forward log" block folded inline |
| Documentation | 2 | Applied — Sources kickoff-brief entry; redundant Task-1 citation dropped |
| Tests / verification | 4 | Applied — P1.5 independence → card-lint, C1.7 additive check, P1.6 sharpened, stance-axis parse |
| Cross-file consistency | 6 | Applied — REQ-E1.5, D-12 gating, REQ-A1.9 → D-9 cite, C1.7 reader scope, D-13 caps, Task-3 cite |
| Claims / evidence honesty | 6 | 5 applied (Ringelmann / Savoia / NIST / Notion / Coda hedges); 1 pre-existing (medical stat) left out of scope |
| Scope / altitude (kickoff) | 6 | Applied — P1.6 softened to SHOULD; Task 3 & 13 effort bumped; altitude D-20 added; Task-17 sequencing noted |

**Altitude check (REQ-H1.3):** bundle-locally, the pinned seed claim ("work one level of abstraction
higher") is a product/pipeline-scope signal, borderline against the autopilot-reflex doctrine axis;
read as correctly untriggered, but the lens pass added D-20 (altitude record, cited from the Goal)
as cheap insurance, and the decomposition already leads doctrine-first.

**Findings dispositioned:** every confirmed finding applied as a spec edit except Cl3
(medical-warning statistic) and F5 (secret-screen on-hit), both pre-existing and left out of scope,
and F6 (Cowork stale-pull) accepted as a v1 minor. No inconsistency halt; no carried open question.

**Validator:** `spec-validate.sh specs/inception` — 0 errors / 0 warnings (re-run post-flip under
errors-block). **markdownlint (`lint:md`):** MD013 is off for specs; markdownlint-cli2 is not
installed locally, so structural markdown lint is deferred to GitHub CI on the head SHA
(degradation noted, per REQ-K1.7).

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-07-13.
Anchor: `e31b1a646b42273cfc09c9b373be2d1c8bbe9d6b` — computed as
`scripts/spec-anchor.sh specs/inception`

Signed off: 2026-07-13 — first activation; Draft→Ready flip on all four spec files.

## 9. Amendment log

### 2026-07-13 — Delta re-sign-off (panel-pairing iteration 1)

Pre-merge correction of the Ready bundle (REQ-D1.4), four edits from an independent
`/panel-pairing` gemini pass, all operator-approved this session:

- **G15** (expression) — Task 2/12 stub-renderer ownership made explicit ("Task 2 ships a
  dashboard-fields-only stub renderer … Task 12 replaces it").
- **F1** (traceability) — Task 8 gains the REQ-J1.4 citation + a per-venture in-session status-view
  deliverable (REQ-J1.4 was orphaned from all task citations).
- **F2** (traceability) — Task 11 gains the REQ-J1.6 citation + graduation-never-auto-chains
  wording (REQ-J1.6 was orphaned).
- **G8** (meaning) — REQ-A1.6 pins the registry rebuild to fire automatically on read-time
  detection of a torn / missing / unparseable registry (operator chose auto-on-read over manual /
  accept-as-is), completing the R7 self-heal decision.

Class: meaning (G8 adds behavior; F1/F2/G15 are traceability / expression).
Lens-pass: independent `/panel-pairing` gemini pass (iteration 1) — 7 findings dropped as not-real
(validated false positives / hallucinations), 6 clarity nits skipped by operator, 4 applied;
validation green (spec-validate 0/0, lint:md, check:links 227 resolve, check:ledger PASS).
Anchor: `139c46769786e15661b7bcc6f4b8ff57586897ba` — computed as
`scripts/spec-anchor.sh specs/inception`

Signed off: 2026-07-13 — delta re-sign-off; no status change (stays Ready).

### 2026-07-15 — Expression-only self-re-anchor (format-version 2 migration)

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
Anchor: `89c87e2103f3c480a19d74b88cd3f5c3fec4c988` — computed as
`scripts/spec-anchor.sh specs/inception`
