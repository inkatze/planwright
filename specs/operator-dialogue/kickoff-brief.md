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
