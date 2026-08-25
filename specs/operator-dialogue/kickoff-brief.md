# Operator dialogue — Kickoff brief

This is the durable contract between human and agent for `specs/operator-dialogue`
(two-brief model, D-3 of `spec-format`). Downstream skills (`/execute-task`,
`/orchestrate`) operate from this brief, not by re-reading the spec.

## 1. Header block

- **Spec path:** `specs/operator-dialogue`
- **Spec commit at walkthrough start:** `161e9b4`
- **Walkthrough date:** 2026-07-17
- **Mode:** first activation (Status Draft, no prior brief)
- **Format-version:** 2 (stored header rests at Ready after sign-off; Active/Done derived)
- **Validator outcome (pre-flight):** `spec-validate` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local override file)
- **Coordination note:** `specs/skill-rigor` is Ready and also edits
  `skills/spec-kickoff/SKILL.md` (mechanical sign-off axis); this spec edits the
  same file on the interaction axis (REQ-F1.4). Reconciliation is walked in §3/§6.

## 2. Goal & glossary

**Restated goal.** At every attended human moment, a planwright skill acts as a
domain expert of the spec that teaches down to the operator's level and
interviews for exactly what it needs, in-band, and never grades the spec on its
own behalf. The skill's judgment lives in doctrine and the rigor passes, not in
a per-run verdict. The evidence is that *one principle is missing* (a doctrine
scoped to only the two authoring skills), not that five skills are each broken —
so the fix lands at doctrine altitude (D-1), the altitude record for the pinned
seed claim ("made for a bot, not a peer").

**Rules out.** Any verdict/score/quality-assessment of a spec by a skill on its
own behalf (the independence firewall — reinforced, never relaxed). Any
weakening of the reserved human controls (never-auto-merge, never-auto-chain,
draft-PR-only, two-key launch, machine-checkable sign-off record + content
anchor). A heavyweight learner model. Wiring the behavioral evals into CI.

**Assumes.** Scope is approval-surfaces-first and kickoff-centered (D-9);
`/spec-walkthrough`'s revamp and the execution-side handoffs are deferred to
later passes. The instruction budget (`check:instructions`) is a hard, shipped
wall every prose change must fit (D-10).

**Glossary (implicit terms surfaced + resolved):**
- *the frontier* — the band between what the operator demonstrably holds and the
  spec's concepts; teaching targets it and fades as uptake shows (ZPD/KST as
  heuristic, not machinery).
- *in-band* — inside the live dialogue where the operator already is; the
  antithesis of the out-of-band `/spec-walkthrough` failure.
- *present without steering* — the IPDAS balance discipline: neutrality covers
  asymmetric detail, leading order, and one-sided framing, not only a stated
  recommendation.
- *operator* — the attended human at a live skill surface (same referent as the
  pipeline's human/adopter, surface-flavored).

**Discipline model (confirmed with operator):** exactly **three** disciplines —
teach to the frontier, interview to completeness, present without steering — with
**self-contained confirmation (REQ-E / D-7) a named rule *under*
present-without-steering**, not a fourth peer discipline.

Signed off: 2026-07-17

## 3. Requirements walkthrough

Eight REQ groups (A–H); count and IDs per `requirements.md`. Per-group intent
restated and confirmed with the operator:

- **REQ-A — the doctrine.** Widen `interaction-style` to govern every attended
  surface; three named inspectable disciplines; manifest citation at every owned
  attended moment; doctrine prose inside the instruction budget.
- **REQ-B — teach to the frontier.** In-band comprehension; comprehend-first;
  pitch-at-frontier-and-fade; lightweight per-concept estimate (no learner
  model); normative tokens preserved verbatim when translating down.
- **REQ-C — interview to completeness.** Goal-directed; no readiness while a
  required decision is undefined; changed upstream answer reopens dependents;
  bounded (~5) per pass; clerical weight on the skill, judgment on the operator.
- **REQ-D — present without steering.** No verdict/score; information-vs-advice
  line; escape valve; IPDAS balance + self-audit; natural-frequency probabilities.
- **REQ-E — self-contained confirmation.** Options restate action+consequence;
  explicit equal-weight reject; no default; no OK/Yes/No; deeper detail
  supplementary (matches `obs:d0753832`).
- **REQ-F — kickoff instantiation.** Instantiate the three at walk and sign-off;
  replace the bare verdict-demand with a "what you're approving / what changes
  downstream" summary; plain-language gate framing; invariants intact; reconcile
  with `skill-rigor`; fit the budget.
- **REQ-G — behavioral eval harness.** Real TTY session; persona driver
  (novice/expert min); grade written artifacts not the pane; independent grader;
  reuse prompt-eval isolation; on-demand only.
- **REQ-H — measurable acceptance.** Split assertable `[test]` vs experiential
  `[manual]`-rubric; named invariant set; CDC/IPDAS rubrics; persona eval is the
  adaptive-level acceptance path.

**Resolved by the agent (reported, not asked):** REQ-C1.1/C1.2's "required
decision" and "reopen dependents" map onto kickoff's *existing* machinery (the
inconsistency-halt and the open-questions-block-sign-off rule). At kickoff the
bundle already exists, so the "dependency structure" backward-chaining runs over
is the bundle's open questions / cross-references, not the task graph (that is
`/spec-draft`'s elicitation surface). REQ-C is read as naming and generalizing
that existing discipline, not adding a new graph engine at kickoff.

**Consolidated spec edits applied this section:**
1. **REQ-A1.3 citation scope — "kickoff-only this pass"** (operator decision).
   `test-spec.md` REQ-A1.3 rescoped so the manifest-citation check greps only the
   attended surfaces instantiated so far (`/spec-kickoff`; `/spec-draft` already
   cites it), the deferred execution-side surfaces citing when reworked. Matching
   clause added to the `tasks.md` "Execution-side handoffs pass" Deferred entry;
   traceability changelog line added to `requirements.md`. Rationale: a manifest
   citation stays an honest promise that the surface already honors the doctrine,
   never a citation ahead of the behavior — aligns with D-9's kickoff-first
   sequencing.

Signed off: 2026-07-17

## 4. Design walkthrough

Reconciled ledger — 11 D-IDs authored this drafting session, all origin `N`
(count and IDs per `design.md`), plus D-12 minted at this kickoff:

- **D-1, D-2, D-3, D-4, D-6, D-7, D-8, D-9, D-10, D-11 — confirmed.** Rationale
  intact; none contradicts a walked requirement.
- **D-5 — confirmed with a kickoff-lens clarification.** Its rationale cites the
  `Dependencies:`/`Done when:` structure, which is the `/spec-draft` elicitation
  reading; at `/spec-kickoff` the same decision reads through the open-questions
  lens (per §3). Same decision, two lifecycle instantiations; not an amendment.
- **D-12 — minted at this kickoff (meaning-class addition).** The
  recommendation-vs-present-without-steering grounding test, reconciling the
  retained "selectors with a recommendation" rule with D-6's balance rules: a
  recommendation is admissible only when its basis is grounded in the spec,
  doctrine, or mechanical consistency (operator-verifiable); a recommendation
  resting on the skill's own quality opinion is stripped by the self-audit. This
  reuses D-3's information-vs-advice line as the switch and unifies it with the
  escape valve. Decided with the operator (option 1 + grounding-test phrasing).

**Firewall (D-3) vs teach-to-frontier (D-4):** resolved by construction via the
information-vs-advice line + escape valve. No inconsistency-halt triggered.

**Consolidated spec edits applied this section:**
1. **D-12 added** to `design.md`.
2. **REQ-D1.4 extended** with the grounding-test sentence; citation updated to
   add D-12.
3. **Task 1 citations** updated to add D-12.
4. **Changelog line** added to `requirements.md`.

Signed off: 2026-07-17

## 5. Verification approach

**Coverage mix** per `test-spec.md` (tags/counts derived there, not copied):
`[test]` on most REQs, a `[design-level]` block for the doc/skill-prose
contracts, `[manual]` rubric-scored experiential edges, mixed tags where a REQ
has both. Honest to the D-11 split; no defaulting to `[manual]`.

**Verification ownership — three lanes** (per-entry membership is derived from
each `test-spec.md` entry body via the intro's self-classification convention,
not copied here — cite-don't-copy):
1. **CI-run structural `[test]`** — greps/structural checks that run in
   `mise run check` / CI (entry body signals "a check greps…" / "a structural
   check asserts…").
2. **On-demand behavioral-eval `[test]`** — assertions over a real kickoff run,
   run through the TTY harness, **never in CI** (REQ-G1.5; the `eval:`-namespaced
   harness is covered by `check-no-ci-evals.sh`; entry body signals "an assertion
   over a kickoff run…").
3. **Manual rubric `[manual]`** — the CDC/IPDAS-scored experiential edges;
   operator sweeps, independent grader scores, human as final rater.

**Dead-path check:** no REQ's verification is unrunnable. REQ-D1.5
(natural-frequency probabilities) is vacuous unless the harness constructs a
scenario where a likelihood is actually surfaced — a Task 6 fixture note, not a
spec defect.

**Consolidated spec edits applied this section:**
1. **`test-spec.md` intro tightened** — the `[test]` tag now explicitly covers
   two subsets (CI-run structural vs on-demand behavioral-eval, the latter never
   a CI gate), so a bare `[test]` is not misread as CI coverage. Confirmed with
   the operator. Changelog line added.

Signed off: 2026-07-17

## 6. Task graph

Reconstructed from `tasks.md` `Dependencies:` lines (authoritative;
`spec-graph.sh` renders the same). Six tasks.

- **Edges:** 1→2, 1→3, 2→3, 3→4, 3→6, 4→6, 5→6.
- **Critical path** (tool-confirmed, effort-weighted, efforts per `tasks.md`):
  **1→2→3→4→6 = 6.5 days.**
- **Parallelism:** Task 5 (eval harness) has no incoming edges — dispatches
  immediately alongside Task 1, joins at Task 6, carries ~1.5d slack.
- **Deliberate non-edges** (do not "fix"): (a) 5 ⊥ {1,2,3,4} — independent,
  fixture-skill-driven test infra; (b) no direct 2→6 edge — transitive via
  2→3→6; (c) 4 ⊥ 5 — calibration independent of the harness.
- **External coordination (cross-spec, not a graph edge):** `skill-rigor`
  (Ready) also edits `skills/spec-kickoff/SKILL.md`; Task 3 (REQ-F1.4) reconciles
  with it. Carried to the risk register.

Signed off: 2026-07-17

## 7. Risk register

**Decision-domains gap check** (11 catalogued domains walked against the spec via
the merged catalog `scripts/resolve-catalog.sh decision-domains`, so overlay
domains counted): auth, deploy-migration, queues-async, versioning-scheme,
dependency-adoption are `n/a` (the harness reuses tmux/jq/panel-backends — no new
dependency; no store/migration/versioning decision). data-storage, caching,
concurrency, observability, secrets-config are touched but dispositioned by reuse
(prompt-eval isolation, positive-footer idle detection, fail-closed teardown,
allowlisted scalar results, documented config). Two **api-surface** gaps —
touched but undecided — are recorded as accepted-risk rows 3 and 4. No catalogued
domain the spec touches is left silently undecided.

| # | Risk | Mitigation / early signal |
|---|------|---------------------------|
| 1 | **Instruction-budget breach (D-10)** — `interaction-style` rework (front-loaded by builder/spec-draft/spec-kickoff) + kickoff SKILL.md rework, both under `check:instructions` start-load walls; kickoff already budget-tight. | Trim/relocate prose (REQ-F1.5); `check:instructions` is the hard early signal (fails the build). Highest-likelihood execution risk. |
| 2 | **`skill-rigor` collision (REQ-F1.4)** — both edit `skills/spec-kickoff/SKILL.md`. | **Pinned sequencing (operator decision): `skill-rigor` lands first; operator-dialogue Task 3 rebases and reconciles onto the merged skill-rigor sign-off changes.** Rationale (grounded, not taste): REQ-F1.3 frames the very gates skill-rigor is hardening; REQ-F1.4's reconcile duty is one-directional (on operator-dialogue); the second-lander eats the SKILL.md conflict and that resolution *is* Task 3's reconcile step; skill-rigor is already closer to merge. **Only Task 3 (transitively 4, 6) carries the constraint** — Tasks 1, 2, 5 don't touch `spec-kickoff/SKILL.md` and proceed in parallel. The dispatcher of Task 3 holds until skill-rigor's spec-kickoff changes are merged. Early signal: SKILL.md merge conflict, or a reverted skill-rigor change caught in self-review. |
| 3 | **api-surface gap — structured decision/transcript log schema** (REQ-G1.3) named but not pinned; it is the contract between the kickoff skill and the independent grader. | Accepted: Task 3/5 pin the schema at execution; keep it documented and versioned. |
| 4 | **api-surface gap — confirmation structural-check input contract** (Task 2 / REQ-E1.1): what representation of an option set the check parses (static SKILL.md blocks vs harness-captured selectors) is undecided. | Accepted: Task 2 decides at execution. |
| 5 | **TTY-harness fragility** — false-idle, partial `capture-pane` frames, ghost-suggestion noise. | Positive-footer-anchor idle detection (decided, Task 5); fail-closed teardown; on-demand-only bounds blast radius; document harness config (personas, grader backend, budget). |
| 6 | **Independence-firewall regression** — instantiation (Task 3) accidentally introduces verdict-shaped phrasing. | REQ-D1.1 no-verdict `[test]` (absence of verdict tokens) + the grounding-test self-audit (D-12). Early signal: the no-verdict assertion fails. |
| 7 | **Dogfooding/recursion** — the kickoff signing this spec off (and running through Tasks 1–6) is the *old* mechanical one until Task 3 lands. | Context, not a defect; low. New behavior applies from Task 3 onward. |
| 8 | **Harness trust-boundary security** — send-keys injection from persona input, structured-log serialization, echo discipline vs "preserved verbatim", worktree teardown containment, third-party grader egress, and a forgeable eval-produced sign-off record (surfaced by the sign-off lens pass). | Named and bound by **REQ-G1.6**: sanitize persona text before `send-keys`; containment-check the teardown path; escape-safe non-code-bearing log; echo-safety on surfaced values; fixture-only content to any third-party grader; eval-only/non-authoritative marking of driver-produced sign-off records. Execution pins the mechanisms; `security-posture` is the doctrine. |

No open questions remain; the two gaps are explicit accepted risks. Data hygiene
(`security-posture`): the register carries no secrets, credentials, hostnames, or
customer detail.

Signed off: 2026-07-17

## 8. Sign-off

**Mode/scope:** first activation; full-bundle lens review.

**Lens review pass (Discovery Rigor, D-45).** Path taken: parallel fan-out, 7
read-only sub-agents covering the 9 canonical lenses over the whole bundle
(non-trivial artifact), followed by an independent `/panel-review --nested` pass
(gemini backend) and a targeted delta convergence check. ~25 lens findings + 10
panel findings, all validated (3-pass) and dispositioned; the fixes are recorded
in the `requirements.md` Changelog and applied across all four files + this brief.

**Altitude check (REQ-H1.3 / autopilot-reflex).** Triggered bundle (doctrine-gap
seed claim). Altitude record D-1 exists, is cited from the Goal, and the task
decomposition is doctrine-first (Task 1 reworks the doctrine). Consistent — no
finding.

**Canonical lens-coverage table (post-disposition):**

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 4 | D-12 reconciliation completed (balance rules carved, D-6/D-7 reconciled); REQ-C kickoff-lens clarified in D-5; REQ-H1.3 self-audit made non-scoring; REQ-D1.5 re-tagged |
| Security | 6 → REQ-G1.6 + panel | send-keys injection, log serialization, echo discipline, worktree teardown, grader egress, forgeable eval sign-off → REQ-G1.6; panel added grader-credential hygiene + publishing-disabled |
| Error handling / failure modes | 1 | grader-failure degradation to human rater (REQ-G1.4) added via panel |
| Performance | n/a | perf = instruction budget (Risk 1); no new finding |
| Concurrency / state | 1 | per-run-unique tmux window + stale reap (REQ-G1.5) added via panel |
| Naming, readability, structure | 3 | D-12 origin-tag legend widened; amendment annotations added; discipline nesting encoded in requirements/design |
| Documentation | 8 | headcount 5/6 fixed; ≤5 threshold hardened; REQ-A1.2 test strengthened; never-auto-merge restored to REQ-F1.4; MAY added; IPDAS expanded; REQ-A1.3 reworded; REQ-B1.5 test corrected |
| Tests / verification | 8 | dead-path tests honestly re-tagged; cheap assertables wired into Task 6; check-no-ci-evals coverage (eval: namespace); intro convention normalized; new REQ-C1.5 |
| Cross-file consistency | 4 | dangling Source citation fixed; brief §5 made cite-don't-copy; REQ-D1.4/G1.4/G1.5/G1.6 test-spec entries mirrored to their REQ obligations |

**Disposition summary.** Lens clusters 1–7: all applied or dispositioned with the
operator (3 forks decided: no-pre-selected-default unconditional; dead-path tests
honest re-tag + wire cheap ones; self-audit non-scoring). Panel pass: 6
refinements applied (S1–S6), 1 new REQ added (REQ-C1.5 input robustness), 1 fork
deferred by decision (calibration-estimate shape → Task 4); 2 panel items dropped
after validation (D1.5 already-fixed, Task-2 file-path is execution's call). Delta
check: 4 test-spec/task mirror-gaps closed. No finding left undispositioned; no
inconsistency halt; no carried open question.

**Reserved controls & invariants:** preserved and, where the lens pass found them
weakened in prose, restored (never-auto-merge back in REQ-F1.4). Independence
firewall reinforced (REQ-D1.1, REQ-H1.3 non-scoring self-audit, REQ-G1.6 eval-only
sign-off records). Reconciliation with `skill-rigor` pinned (Risk 2 sequencing).

Class: meaning
Lens-pass: §8 lens review pass (full-bundle fan-out + panel + delta check), all findings dispositioned
Anchor: `bcdc1af4d5f65f50b1abcd4c8b91cae25b243a7e` — computed as
`scripts/spec-anchor.sh specs/operator-dialogue`

## 9. Amendment log

### Amendment 1 — expression-only lint fix (2026-07-17)

Pre-merge, expression-only correction on the spec PR (#225): added the eight
`## REQ-<Group> — <theme>` section headers to `test-spec.md` so its entries nest
under h2 group headers (h1→h2→h3), fixing `lint:md` MD001/heading-increment. The
drafted bundle omitted these headers and first hit CI on this PR. No requirement,
decision, task, or verification content changed — the sign-off record in §8
stands; this entry only re-anchors over the corrected file bytes.

Class: expression-only
Changelog: requirements.md 2026-07-17 "Post-sign-off lint fix (pre-merge, expression-only)" entry
Anchor: `82446f907709532272d872f1a2cbaeeebd55d398` — computed as
`scripts/spec-anchor.sh specs/operator-dialogue`

### Delta re-walkthrough — extension kickoff (2026-08-24)

Reopened-bundle scoped kickoff (the reopen cycle, kickoff-lifecycle
REQ-A1.6: extending a Done bundle reopens it to Draft; on this
format-version 2 bundle Done was derived, so the stored headers flipped
Ready→Draft — spec-format's v2 reopen — when `/spec-draft --extend` ran on
2026-08-24). Walkthrough scope, confirmed with the operator: the extension
delta only — REQ-I–REQ-M, D-13–D-21, Tasks 7–13, the consumed execution-side
deferral, and the amended Goal/Scope/Sources — walked in the delta
re-walkthrough shape; the signed base sections (§§1–8 above) stand and are not
re-walked. Spec commit at walkthrough start: 968646c. Validator at pre-flight:
0 errors, 0 warnings. Sign-off flips Draft→Ready again.

**§2 (delta) — Goal & glossary.** Agent restatement of the extension's thesis
stood uncorrected: the recurrence of walls is structural (two mandatory rule
sets colliding at the turn with no arbitration, and an unmeasured output
side), so the delta adds the arbitration (REQ-I), the corpus repair (REQ-J),
the execution-surface pass consuming the deferral on evidence (REQ-K),
capture-at-birth with tracking left downstream (REQ-L), and output-side
enforcement (REQ-M) — without re-litigating D-1 (per D-13). Two implicit
terms resolved with the operator:

1. *"The companion bundle"* — named once in a new Sources entry
   (`specs/action-item-ledger`); REQ/D prose keeps the role phrasing, and
   REQ-L1.2 cites the entry. Chosen over inline naming (rename-fragile) and
   over leaving it unnamed (undiscoverable).
2. *"Dispatch-gate record"* (REQ-L1.4's third ship-gate form, defined
   nowhere) — replaced with "an Awaiting-input entry", aligning REQ-L1.4
   with REQ-L1.2's tracked-state vocabulary so every ship-gate form has a
   named reader and drain ritual; the REQ-L1.4 test-spec entry mirrors the
   same wording. Chosen over minting and defining a new concept and over
   narrowing to two forms.

Consolidated spec edits so far: requirements.md (REQ-L1.4 vocabulary,
REQ-L1.2 citation, the companion-bundle Sources entry), test-spec.md
(REQ-L1.4 entry vocabulary).

Signed off: 2026-08-24

**§3 (delta) — Requirements walkthrough, groups I–M.** Group intents
restated and confirmed: I (the arbitration and projection shape), J (the
corpus repair), K (the execution-surface pass), L (capture-at-birth), M
(output-side enforcement). One fork surfaced and decided: REQ-J1.1's
repair-only bar contradicted its test-spec entry's
repair-or-recorded-disposition bar; the operator chose the wider bar —
REQ-J1.1 now reads "repaired or carry a recorded disposition — none survives
silently exempted", matching the test-spec and the applied/declined/deferred
disposition model the lens passes use. No other gap or edge case in the five
groups required a decision; the L-group vocabulary fix was taken in §2.

Consolidated spec edits after §3: the §2 list plus requirements.md
(REQ-J1.1 bar widened).

Signed off: 2026-08-24

**§4 (delta) — Design walkthrough, D-13–D-21.** Reconciled ledger, all nine
**confirmed** with rationale intact; none superseded. *(Corrected at the
sign-off lens pass: the walk's "no base decision touched, none in
contradiction" claim missed that D-9's decision text still asserted the
execution-side deferral REQ-K consumes — D-9 now carries the consumed-
deferral amendment annotation, and D-16/D-17/D-18/D-19/D-20/D-21 were
completed or clarified per the lens dispositions below.)* D-13
records the altitude call that D-1 stands un-relitigated. D-13 extension
altitude (doctrine/mechanism/values split) · D-14 the arbitration · D-15
projection shape · D-16 `/polish` worktree-local cache (the two-brief
model's cache class, the classification REQ-J1.2 leans on) · D-17 step-report
slots · D-18 capture-at-birth with degradation path · D-19 enforcement via
the shipped harness, sidedness check advisory · D-20 qualitative density
bound, numbers in fixtures · D-21 no monotonic summary (retitled at the lens
pass from "no monotonic accumulator").

Signed off: 2026-08-24

**§5 (delta) — Verification approach.** Coverage mix reviewed: on-demand
behavioral lane carries most `[test]` claims (eval invariants, fixtures, and
the Task-13 acceptance join); CI-run slices are K1.3's script-level unit
test, M1.3's check-behavior test, and M1.4's `check-no-ci-evals` guard;
`[design-level]` covers statement-existence and named-human-review entries
(I1.1, L1.2, and the design-level halves of J1.1, K1.2, L1.4, M1.2);
`[manual]` residue is swept by the human as final rater — at the acceptance
join, except L1.4's half, which the human verifies at each kickoff sign-off.
Ownership unchanged from the base bundle's model; REQ-M1.4 keeps the
harness out of CI. *(Corrected at the sign-off lens pass: the walk's
"dead-path check: none found" was wrong — the CI-run slices also include
K1.1's manifest grep and M1.3's check-behavior unit test, and the
dead-verification lens found the turn-shape assertions unobservable against
the shipped harness and several fixtures and check-widenings unowned;
resolved by the cluster F and G dispositions below, which give every named
verification a runnable home and an owner.)* One finding decided: REQ-M1.2's
test-spec heading used two bracket groups with prose between (out of tag
grammar, sweep-miscount risk) and claimed `[test]` while its body describes
the file itself as the verification; retagged to a single conforming
`[design-level]` group with the heading reworded. Chosen over a mixed
`[test + design-level]` retag (no test of its own to claim) and over leaving
it as written.

Consolidated spec edits after §5: the §3 list plus test-spec.md (REQ-M1.2
heading retag).

Signed off: 2026-08-24

**§6 (delta) — Task graph, Tasks 7–13.** Graph reconstructed from the
`Dependencies:` lines (authoritative; effort figures cite the task blocks):
7 roots the delta; 8 follows 7; 9 and 10 fan out on 7 alone; 11 and 12 fan
out on 7+8; 13 joins 9–12. Effort-weighted critical path 7 → 8 → 11-or-12 →
13; widest concurrent window runs the 9/10/(11|12) lanes together.
Deliberate non-edges recorded so nobody "fixes" them later: 9/10/11 carry no
edges among themselves (largely disjoint surface sets, drafting-session
decision); 12 does not depend on 9–11 (invariants build against fixtures;
surfaces meet invariants only at 13); no edge 12→base-Task-5 or
13→base-Task-4/5 (the harness and personas they reuse are Completed,
dependencies trivially satisfied). *(Added at the sign-off lens pass: Tasks
8 and 10 both edit `skills/spec-kickoff/SKILL.md` with no edge between them
— either order works, so no dependency is added, but they should not run
concurrently; the orchestrator serializes or bundles them.)* One ownership gap decided: authoring-surface capture (which Task
13's kickoff-run assertion exercises) lives **doctrine-only via Task 8** —
the capture rules land in doctrine the authoring surfaces already load at
run-start, per the base D-1 altitude bet (doctrine over per-skill patching);
no task edit, this reading recorded instead. Chosen over extending Task 10
(couples the repair lane to capture) and over minting a new task.

Signed off: 2026-08-24

**§7 (delta) — Risk register.** Decision-domains gap check run against the
merged catalog (`scripts/resolve-catalog.sh decision-domains`): domains the
delta touches and already decides — data-storage/caching (D-16 cache file),
observability (D-19 advisory check), existing-seam-reuse (harness, two-brief
model, accumulator targets; reuse notes present), human-comprehension (the
spec's subject), llm-output-quality (rows 2 and 6 below). No catalogued
domain is touched-but-undecided after row 6's acceptance. Delta rows,
appended to the base register (numbering continues from base row 5):

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 6 | **Ledger-cutover semantics** — REQ-L1.2 targets the companion ledger "once it ships"; the cutover (re-pointing the doctrine target list, migrating pre-ledger captures) is defined in neither bundle. | Accepted as an interface expectation, decided with the operator: **the companion bundle owns the cutover** (it ships the mechanism, so it ships the re-point; its kickoff should carry the item). Early signal: the ledger ships while capture doctrine still names only the accumulator surfaces. |
| 7 | **Turn-shape invariant brittleness** — LLM-driven eval runs are non-deterministic; invariants assert over transcripts. | Fixtures pin a known wall failing and a known projection passing (REQ-M1.1); experiential residue stays human-rated (REQ-M1.2). Early signal: the same fixture flapping across runs. |
| 8 | **Doctrine-only capture delivery** (residual of the §6 decision) — capture rules landing in a doc the authoring surfaces don't load defers the failure to Task 13's kickoff assertion. | Task 8 review checks the authoring surfaces' run-start doctrine covers the capture rules' home. Early signal: a manifest with no path to them. |
| 9 | **Instruction-budget pressure from the repairs** — Tasks 9–11 add citations and bounded-form prose to skills near budget. | Each task's Done-when requires the instruction-budget check green. Early signal: budget failures forcing prose trade-offs mid-repair. |
| 10 | **Self-reported turn mirror** (accepted residual of the cluster-F decision) — surfaces mirror their own turn output into the log the eval grades, so pane-vs-log divergence is the remaining pencil-whip surface. | Accepted: the mirror is the same emit path as the turn (divergence takes deliberate forking); REQ-G1.3's artifact-only rule stays intact. Early signal: an eval pass on a surface the operator experiences as walling. |

Operator cold-review additions: none. No open question carried.

Signed off: 2026-08-24

**Sign-off lens review pass (Discovery Rigor, D-45; delta-scoped, meaning-class).**
Artifact class: **spec** (`artifact-lenses` selection; the spec lens set below).
Path taken: parallel fan-out, one read-only sub-agent per lens (9 agents) over
the extension delta plus the walk edits, after tool-grounded discovery
(`spec-validate` 0/0, `markdownlint` 0 errors). Validation scoping, declared:
full three-pass on findings recommended for immediate spec edits (sub-agent
file-grounded quote → independent grep spot-check → cross-lens convergence),
adversarial re-validation over that same recommend-set (two findings
downgraded: the Scope in/out double-listing already carries the conforming
amendment annotation; the "opposite deferral-gate dispositions" dissolve —
the two gates test different premises and the changelog states the adverse
resolution explicitly); soft-floor spot-check on findings routed to operator
judgment, which the operator finishes at disposition.

**Altitude check (REQ-H1.3 / `autopilot-reflex`):** triggered bundle (the
operator report's seed claims). D-13 exists, is cited from the Goal's
extension paragraph, and the decomposition matches its three-altitude split
(doctrine Tasks 7–8 root the graph; mechanism in Task 12; numbers in
fixtures). No finding.

**Canonical lens-coverage table (spec lens set; pre-disposition):**

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness / internal consistency | 14 (16 raw, 2 refuted) | Stale base surfaces the delta reverses (D-9, REQ-A1.3, tasks.md intro, base-brief assumes clause); L1.1 record-at-birth vs L1.3 confirm-first; J1.5/J1.2 absolutes vs D1.3 escape valve; I1.5 vs E1.1/E1.4; M-group vs G1.3 artifact-only grading; M1.2 vs its own entries; J1.1 corpus bar vs untouched surfaces |
| Ambiguity / interpretation forks | 82 raw → ~14 root forks | Undefined load-bearers: attended surface/turn, wall, bounded, emit mandate, governing artifact, one-request; instance-set granularity; residue bounding; capture ordering/boundary; ledger cadence; M1.1 floor; sidedness declaration form; K1.3 change semantics |
| Citation / coverage integrity | 8 | Dangling test-spec A1.3 pointer; 2 orphan Sources entries; I1.5 missing sweep cite; K1.1 token content mismatch; Task 11 missing REQ-A1.3/D-9 cites; brief REQ-A1.6 unqualified + reopen-flip frame; walk-edit changelog pending |
| Dead verification paths | 15 | Most eval-`[test]` claims unobservable against the shipped harness (grades sign-off.json + decision-log.jsonl only, no turn record; fixtures are deterministic stand-ins; personas stub-bound); check-doctrine-manifest widening, fleet/watch unit test, sidedness fixture unowned |
| Decision-domain gaps | 12 | Capture write path into tasks.md vs single-writer reconcile/lock/guard; cache-file storage class + lifecycle; decision-log schema growth vs G1.3; nested handoff contract; watch-silence liveness; sidedness-check seam + reader; corpus-repair rollout window; eval gate thresholds/cadence |
| Testability of Done-when | ~25 | Per-skill `check:instructions` scoping does not exist; content-bearing clauses judge-only; Task 11 needs Task 9's `/execute-task` work; Task 12 fixture authorship; Task 13 scope/flip mechanic/rubric artifact unbounded or undefined |
| Cross-file consistency | 30 | §A both walk edits landed cleanly, headers mirrored, changelog-vs-diff exact; stale-base items above; 8 test-spec assertions with no authoring task; taxonomy/preamble drift; sweep-record misdescriptions (gate-wiring dual emission, /execute-task CI routing, fleet/watch referent); D-16 vs accumulator-taxonomy/gitignore; brief §4/§5/§6 delta-section errors |
| Documentation / glossary drift | 19 | "projection" vs derived projection; "accumulator" second sense; "ledger" three referents; "tracked state" vs accumulator; disciplines population; gate compounds; level-triggered; capture vs capture-pane; lane; minor: invariant, observations-log name, log-name truncation |
| Rendered-content safety | none | Fences balanced, parse patterns confined, byte hygiene clean, no secrets |

**Merged disposition clusters (deduped across lenses; dispositions recorded
per cluster below as decided):**

- **A. Stale-base reconciliation** — annotate D-9 (deferral consumed for the
  four execution surfaces; `/spec-walkthrough` deferral stands), annotate
  REQ-A1.3 (three stale spots incl. requirements.md line-496 area), rewrite
  the test-spec REQ-A1.3 entry (dangling Deferred pointer), extend the
  tasks.md intro narrative to the 7→13 lane, note the base-brief §2 assumes
  clause superseded in this entry.
- **B. Citation & Sources hygiene** — cite or fold the two orphan Sources
  entries; add the sweep cite to REQ-I1.5; ground REQ-K1.1's
  drafting-session token (or widen that Sources entry's text); add
  REQ-A1.3/D-9 to Task 11's citations; qualify the brief's REQ-A1.6 cite and
  state the reopen flip in both frames (derived Done; stored Ready→Draft);
  changelog entry covering all walk and lens edits.
- **C. Sweep-record evidence corrections** — gate-wiring loop-end handoff
  records artifact-side destination only (turn-side half is undeclared, not
  dual-mandated); `/execute-task` routes full CI output to Awaiting input
  (artifact), not at the operator; fleet/watch: the render mandate lives in
  `orchestration-modes.md` (the attention surface), `fleet-attention-watch.sh`
  is already change-driven and `fleet-dashboard.sh watch` writes a file
  artifact — retarget REQ-K1.3/Task 11/sweep instance accordingly;
  `finding-categorization` already declares the four tables artifact-side
  ("they are not prompts") — the recorded instance retargets to composed
  in-turn presentation or is dropped; reconcile D-20/Task 7's "density bound"
  with the existing Small-bites rule (extension, not new mint).
- **D. Capture write path** (decision fork) — who writes/commits captures
  into `tasks.md`, on which branch, under what lock/reconcile interaction,
  the guard/gate shape of captured entries, homeless-skill captures,
  propose-confirm vs write-then-confirm ordering (L1.1 vs L1.3), action-item
  boundary, whether the L1.2 target list is exhaustive.
- **E. `/polish` cache file** (decision fork) — storage class, named
  reader/drain ritual, gitignore entry ownership, filename, overwrite/append
  lifecycle, nested-mode contract (projection return vs gate-wiring's
  collapsed-is-not-abridged PR body).
- **F. Eval observability** (decision fork) — how turn shape becomes
  gradeable given REQ-G1.3's artifact-only rule (log schema growth + emitter
  ownership vs pane exception vs narrowed invariants), fixture ownership for
  the eight orphan test-spec assertions, M1.1 floor-vs-full-set, M1.2
  residue wording, pass thresholds and post-Task-13 cadence.
- **G. Check-ownership task edits** — check-doctrine-manifest widening
  owner; fleet/watch unit-test owner and referent; sidedness-check wiring
  reading (M1.4 vs its test-spec entry) and fixture home; `/execute-task`
  manifest-citation owner (Task 9 vs 11); Task 12 fixture authorship; Task
  13 "flipped to verified" mechanic and rubric-record home; replace
  non-existent per-skill `check:instructions` phrasing in Done-whens.
- **H. Terminology repairs** — disambiguate or rename: turn projection (vs
  derived projection), the J1.3 accumulator sense, the three ledger
  referents, tracked state vs accumulator, the disciplines population,
  ship-gate registration, D-17 level-triggered wording, capture vs
  capture-pane note, lane senses; define attended surface/turn in the
  bundle.
- **I. Residual REQ-level forks** (decision) — governed attended-surface set
  (incl. `/spec-walkthrough`, `/offload` exemption or inclusion); wall
  definition for fixtures; emit-mandate definition + sidedness declaration
  form; one-request meaning; J1.2 residue bounding; J1.5 vs D1.3 precedence
  (operator-requested detail); L1.1 owed-decision vs C1.1 no-open-questions;
  L1.5 ledger cadence vs J1.3; I1.5 vs E1.1/E1.4 layer rule; K1.3
  change/render semantics vs D-17.

Self-critique pass: under-represented areas re-scanned (obs-fragment framing
vs REQ framing; `/orchestrate` emits no structured log today — folded into
cluster F; `/offload` governed-set membership — folded into cluster I; effort
totals sane). Nothing further added.

**Dispositions (clustered-decision mode, operator-chosen; every cluster
decided 2026-08-25, all findings applied, declined-with-rationale, or
deferred-named — none silently exempted):**

- **A — applied** (5 of 6; one member dissolved on validation: the third
  "stale deferral" hit was a frozen 2026-07-17 Changelog entry, historical
  record, no edit). D-9, REQ-A1.3, and the test-spec A1.3 entry annotated or
  rewritten; tasks.md intro extended; the base-brief §2 assumes clause is
  hereby noted superseded on the execution-side half (its `/spec-walkthrough`
  half stands).
- **B — applied** (all 6): Sources tokens, cites, Task 11 citations, the
  qualified reopen frame above, and the 2026-08-25 Changelog entry.
- **C — applied** (all 5): sweep record corrected against the live surfaces;
  REQ-K1.3/Task 7/Task 11 retargeted.
- **D — decided: confirm-then-write as v2 human-owned payload** (REQ-L1.1/
  L1.2 and D-18 amended; pre-ledger target set pinned; capture-not-a-bypass
  clause added).
- **E — decided: full class-1 specification of the /polish cache** (D-16
  amended: `.claude/polish-audit.md`, gitignore entry via Task 9,
  overwrite-per-run, nested drain = parent folds full record into the PR
  body; standalone drain = `/resume`).
- **F — decided: additive turn-record schema growth** (D-19 and REQ-M1.1
  amended; Tasks 9–11 gain the mirror obligation, Task 12 owns every
  fixture and the thresholds; standing-cadence Deferred entry added; risk
  row 10 records the self-reported-mirror residual).
- **G — applied** (all 7): ownership assigned in Tasks 9/11/12/13; Done-when
  clauses made agent-evaluable.
- **H — applied** (all 9): definitions added to REQ-I's intro; renames
  landed (turn projection, monotonic summary, open-captures list, D-21
  retitle, D-17 state slot, ship-gate definition, capture disambiguation).
- **I — applied** (all 10): resolutions landed in the REQ texts (governed
  set with explicit `/spec-walkthrough`/`/offload` deferral, structural wall
  definition, emit-mandate definition and heuristic sidedness form,
  one-request meaning, projected residue, requested-detail precedence,
  capture-not-a-bypass, open-captures cadence, preview alignment with
  REQ-E1.1/E1.4, K1.3 transition semantics).

Also two refuted findings (adversarial pass, recorded as declined): the
Scope in/out double-listing (the out-of-scope bullet already carries the
conforming amendment annotation) and the "opposite deferral-gate
dispositions" (the two gates test different premises; the changelog states
the adverse resolution explicitly).

**Sign-off (2026-08-25).** Delta re-walkthrough complete, all seven delta
sections signed, no inconsistency halt, no carried open question, every lens
finding dispositioned (clusters A–I above). Pre-flip gates: `lint:md` 0
errors; `spec-validate` 0 errors, 0 warnings at Ready; `mise run check` exit
0; recorded claims re-derived (the qualified `kickoff-lifecycle REQ-A1.6`
citation against its source; the four consumed observation fragments on
disk; REQ↔test-spec coverage via the validator). Stored status flipped
Draft→Ready on all four files, `Last reviewed:` 2026-08-25; changelog entry
2026-08-25 records every walk and lens edit. Operator approved via the
shared-understanding summary; merge of the spec PR remains the second key.

Class: meaning
Lens-pass: this delta re-walkthrough entry's sign-off lens review pass
(spec-set fan-out, coverage table, and cluster dispositions above), all
findings dispositioned
Anchor: `8456e842144aa29693219837b9b69d2b6523ab12` — computed as
`scripts/spec-anchor.sh specs/operator-dialogue`
