# Prompt Hygiene — Kickoff Brief

<!-- Component 1: Header block (written first; no sign-off) -->

- **Spec path:** `specs/prompt-hygiene/`
- **Spec commit at walkthrough start:** `04c8702e86a71666748ea18ff16defbecb1ae4d4`
- **Walkthrough date:** 2026-07-08
- **Mode:** First activation (Status Draft → Ready on sign-off)
- **Validator outcome (pre-flight):** `spec-validate: 0 error(s), 0 warning(s)` (clean; Draft findings would be warnings)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local override)
- **Rule docs resolved:** spec-format, discovery-rigor, validation-rigor, security-posture, decision-domains, interaction-style (all present; no degradation)

<!-- Component 2: Goal & glossary -->

## 2. Goal & glossary

### Goal restatement (agent's own words)

planwright's instruction files — the `SKILL.md` bodies the harness injects at
skill invocation, and the `doctrine/*.md` rule docs skills front-load at run
start — grow monotonically as features land, and instruction-following
measurably degrades as that instruction context bloats. Today nothing measures
or bounds it (`/orchestrate` is ~6,900 words against a ~4,250-word ceiling; one
invocation can pull 12k+ words before any work begins). The spec (a) **measures**
the problem via an audit ranking every file and every skill's per-invocation
load, and (b) **installs standing mechanisms so bloat cannot recur silently**: a
CI size-budget guard in `mise run check`, an authoring doctrine rule making
progressive disclosure the norm (skills carry the flow; rule docs carry the law;
bulk and rare branches load at point of use), executed diets on the worst
offenders, and one diet verified behaviorally through a kept regression eval.

### What it rules out

- **Semantic-quality enforcement in CI.** Size and load are the *enforceable
  proxies*; a file can be long-and-structured or short-and-muddled. Quality
  stays review-time human judgment. This is the load-bearing boundary.
- **Output artifacts** (PR bodies, accumulators, generated views) →
  `specs/output-hygiene` (family boundary, not a fold).
- **Runtime session-context management** (`context_budget_threshold`,
  auto-heal) → `specs/orchestration-fleet`.
- **Human-facing docs** (`docs/*.md`, `README.md`) and **spec bundles under
  `specs/`** (content the pipeline processes, not instructions that drive it).
- **Per-commit CI execution of behavioral evals** and **adopting any eval
  framework / new runtime dependency**.

### What it assumes

- Word-count / load correlates with the cited degradation mechanism (D-11's
  fixed source set). The bridge from "budget words" to "preserve
  instruction-following" is an assumption, defended by keeping one behavioral
  eval as the reality check (D-12).
- Behavioral verification is worth *keeping* but not worth running per-commit
  (D-8): deterministic checks gate merges; sampled behavioral checks gate
  prompt edits when they change.
- The doctrine doc and this bundle's own additions must pass the budgets they
  introduce (self-application, design cross-cutting concerns).

### Glossary (implicit terms surfaced)

| Term | Resolution |
| --- | --- |
| **mandatory-at-start load** | SKILL.md words + words of every rule doc the skill's manifest marks *run-start*. The tight budget. |
| **reachable closure** | mandatory-at-start + every rule doc reachable via *point-of-use* manifest entries. The loose budget. |
| **doctrine manifest** | machine-parseable per-skill declaration (D-3) classifying each rule-doc load run-start vs point-of-use; feeds closure computation, resolution check, and the skill's own reading model. |
| **diet** | slimming an offender until it passes the guard, moving law *verbatim in meaning* to rule docs (no contract change rides a diet, REQ-D1.1). |
| **kept eval** | a fixture suite retained in the repo, run on-demand / on-change (not per-commit), pass^k gated (D-7). |
| **offender** | a file over its per-file floor **or** a skill over its start-load / closure budget — the shortlist targets. |
| **pass^k** | all of k runs must pass (vs pass@k = any of k); default k=3; never gate a merge-relevant judgment on a single stochastic run (D-7). |

### Recorded resolutions

- **R2.1 — Proxy/eval relationship (confirmed by human):** the size guard is the
  cheap always-on proxy; the kept behavioral eval is the ground-truth backstop
  that catches the case where a file passes the size budget yet still degrades
  behavior. The eval is the hedge against the proxy being wrong, not merely a
  diet-safety check.
- **R2.2 — Audit-scope reconsideration (human asked to reconsider; carried to
  §3 REQ-A for disposition):** the "instruction file = `skills/*/SKILL.md` +
  `doctrine/*.md`" definition has two concrete edges, both grounded against the
  live corpus:
  - `doctrine/README.md` is *matched by* the `doctrine/*.md` glob but is an
    index, not a rule doc, and no manifest loads it at run start. The audit will
    rank it and the per-file floor will apply, yet it never charges a closure.
    Disposition owed: exempt-as-index vs. let it sit under floor naturally.
  - The SessionStart `scripts/tool-discovery.sh` hook injects `additionalContext`
    (the "Project tooling" block) into every session — a real model-loaded
    instruction surface, but **dynamically generated**, so no static file-walk
    audit can rank it. Outside both globs by nature. Disposition owed: name it
    as a known non-covered surface (Out of scope / risk row) vs. expand scope.
  - Confirmed non-surfaces: `hooks/hooks.json` (config, no prose), the
    `tasks-pr-sync.sh` PostToolUse hook (emits no `additionalContext`), and
    planwright ships no `agents/` definitions.

Signed off: 2026-07-08

<!-- Component 3: Requirements walkthrough -->

## 3. Requirements walkthrough

### REQ-A — Measurement & audit

**Intent:** measure the problem before bounding it — per-file word counts,
per-skill manifest-derived start-load and closure, a ranked report, an
offender shortlist with a per-offender diet plan.

**Corpus measurement (grounding, 2026-07-08):**
- SKILL.md over per-file error (4,250): `/orchestrate` 6,913, `/execute-task`
  4,954, `/spec-kickoff` 4,375 — **exactly** Tasks 5/6/7's targets.
- doctrine over per-file error (4,000): `spec-format.md` 4,099 — Task 7's.
- So the per-file offender set is correctly and completely scoped.

**Decisions / edits:**
- **REQ-A1.1** now excludes `doctrine/README.md` (index, not run-start law,
  loaded by no manifest) from the per-file walk. *(human: exclude as index.)*
- **REQ-A1.3** clarified: the offender shortlist covers **skills over the
  start-load / closure budget**, not only files over per-file floors — the
  crux of the start-load gap below.
- **REQ-A1.4 (new):** the audit also identifies `additionalContext` /
  `hookSpecificOutput`-emitting hooks and measures their **static** injected
  prose (dynamic interpolations noted, not counted), reported as a distinct
  injected-context class. *(human: expand scope to injected templates. Live
  instance: SessionStart `tool-discovery.sh`, ~40 static words today.)*

### REQ-B — Instruction guard

**Intent:** a `mise run check` guard mirroring the sibling checks — per-file
floors (secondary), a tight start-load budget and a loose closure budget
(primary, D-1), all overlay-tunable knobs; a reason'd exemption suppressing
**only** the per-file floor (never start-load/closure); a resolution check.

**Decisions / edits:**
- **REQ-B1.7 (new):** injected static prose (REQ-A1.4) carries a **warn-level
  floor only** — growth reported, CI never fails on a per-session partly
  dynamic surface. Default knob + options-reference row. *(human: audit +
  warn-only floor, over full-error-budget or report-only.)*
- Confirmed the exemption/start-load interaction: REQ-B1.3 forbids exempting
  the start-load budget, so a start-load offender has **no escape valve** —
  it must be dieted. This is what makes the start-load gap a must-fix.

### REQ-C — Authoring doctrine

**Intent:** `doctrine/instruction-hygiene.md` defining the authoring rule
(flow in skills, law in rule docs, refs one level deep), the loading
convention with the safety floor (gating law never deferred), the
test-and-measure principle, and the kept prompt-eval convention (fixture
format, dependency-free runner, pass^k default k=3, on-change/on-demand
cadence, per-run cost). Confirmed intact; no edits. The safety floor
(REQ-C1.2: gating law SHALL NOT be deferred) is the load-bearing guard that
keeps the diets from moving permission law out of reach — probed and sound.

### REQ-D — Diets & verification

**Intent:** slim each shortlisted offender until it passes the guard, law
moved verbatim in meaning; verify one diet behaviorally (the `/orchestrate`
pilot, D-12); end with zero grandfathered errors.

**The central finding (start-load gap) and its resolution:**
- The task graph pre-committed diet Tasks 5/6/7 to the three per-file
  offenders. But the **primary** budget (D-1, mandatory-at-start, error
  10,000) is manifest-derived and catches doctrine-heavy small-bodied skills:
  `/spec-draft` measures **≈10,460** (2,482 body + 7,978 run-start doctrine,
  `spec-format` 4,099 dominant) — **over the error threshold, with no diet
  task and no exemption path.**
- **Coupling:** `spec-format` is the dominant run-start load for both
  `/spec-draft` and `/spec-kickoff`; Task 7 is allowed to *exempt* it (keep
  it large), which would strand both dependents over start-load.
- **Resolution (human: add start-load remediation scope):** REQ-D1.1
  clarified to include start-load/closure offenders; new **Task 7.5** diets
  any start-load offender the Task-3 computation surfaces (point-of-use
  reclassification); Task 7 records the spec-format→dependents coupling;
  Task 8 depends on 7.5. New D-13 records the injected-context decision.

### Consolidated spec-edit list (applied in place, Draft)

1. `requirements.md`: REQ-A1.1 README exclusion; REQ-A1.3 + REQ-D1.1
   shortlist covers start-load offenders; **new** REQ-A1.4 (injected-context
   measurement) + REQ-B1.7 (warn floor); Changelog entry.
2. `design.md`: **new** D-13 (injected-context, warn-floor); cross-cutting
   notes for the start-load offender set / spec-format coupling and the
   README exclusion.
3. `tasks.md`: **new** Task 7.5 (residual start-load diets); Task 2 extended
   (injected-context measurement, warn floor, README exclusion, shortlist to
   Task 7.5); Task 7 spec-format-coupling note; Task 8 dep +7.5; dependency
   view + critical path updated (1 → 2 → 3 → 5 → 7.5 → 8).
4. `test-spec.md`: **new** REQ-A1.4 + REQ-B1.7 entries; coverage-mix count
   corrected (was "11 of 16", pre-existing drift → now "15 of 20").

Validator re-run after edits: `0 error(s), 0 warning(s)`; full REQ↔test-spec
coverage confirmed.

Signed off: 2026-07-08

<!-- Component 4: Design walkthrough -->

## 4. Design walkthrough

Every D-ID accounted for; no design decision contradicts a walked
requirement (checked explicitly).

| D-ID | Status | Note |
| --- | --- | --- |
| D-1 budget start-load; per-file secondary | Confirmed | The start-load finding validates it — per-file missed `/spec-draft`; primary caught it. |
| D-2 words unit, 500-line-derived thresholds | Confirmed | Grounded by measurement (4,250 SKILL error caught exactly 3; 10,000 start-load caught `/spec-draft`). |
| D-3 doctrine manifest | Confirmed | Start-load computation (Task 3) rests on it. |
| D-4 one guard script | Confirmed | — |
| D-5 config thresholds + exemptions | Confirmed | Extended consistently by REQ-B1.7's warn-floor knob. |
| D-6 bespoke sh eval runner | Confirmed | — |
| D-7 pass^k k=3 | Confirmed | — |
| D-8 on-demand evals | Confirmed | — |
| D-9 loading convention + safety floor | Confirmed | Task 7.5 applies run-start → point-of-use. |
| D-10 instruction-hygiene.md home | Confirmed | — |
| D-11 degradation citation set | Confirmed | — |
| D-12 /orchestrate pilot | Confirmed | — |
| **D-13 injected-context, warn-floor** | **New (this walk)** | Records the human's audit-scope expansion. |

**Follow-through note:** REQ-B1.5 grounds the four main budget defaults; the
new injected-context warn-floor default (REQ-B1.7) is left as a Task-2
authoring detail (ground it in the measured injected size + headroom, same
test-and-measure discipline) rather than minting a requirement — the surface
is ~40 words today. Not a blocker; revisit if the surface grows.

Signed off: 2026-07-08

<!-- Component 5: Verification approach -->

## 5. Verification approach

- **Coverage mix (post-edit):** 20 REQs — 15 carry `[test]` (GitHub CI via
  `mise run check` / `mise run test`), 4 `[design-level]` (B1.5, C1.1, C1.2,
  C1.3), 1 `[manual]`-only (D1.3); the rest mixed `[test + manual]`. The eval
  runner's *logic* is tested against a stubbed `claude` on PATH, so no CI run
  spends tokens (D-8).
- **Ownership:** deterministic `[test]` entries run in GitHub CI. `[manual]`
  entries are swept by the human at PRs: the Task-2 diet plans (REQ-A1.3) and
  the pilot before/after eval artifacts under `tests/prompt-evals/`
  (REQ-D1.3). Real behavioral eval runs never execute in CI, by design (D-8).
- **Dead-path check:** none. Every REQ's named verification can run — the
  pilot eval is on-demand and artifact-recorded; REQ-A1.4 / REQ-B1.7 are
  fixture-based in CI.
- **Discovered inconsistency (fixed during §3):** the coverage-mix intro had
  drifted from the REQ set (claimed "11 of 16"; the bundle held 18 REQs, 13
  `[test]`). Corrected to the true count (now 20 REQs, 15 `[test]`).

Signed off: 2026-07-08

<!-- Component 6: Task graph -->

## 6. Task graph

Reconstructed from the authoritative `Dependencies:` lines (Task 7.5 added
this walk):

- Task 1 → {Task 2, Task 4}
- Task 2 → Task 3
- {Task 2, Task 3} → {Task 6, Task 7}; {Task 2, Task 3, Task 4} → Task 5
- {Task 3, Task 5, Task 6, Task 7} → Task 7.5
- {Task 5, Task 6, Task 7, Task 7.5} → Task 8

**Critical path (effort-weighted):** `1 → 2 → 3 → 5 → 7.5 → 8` ≈ **6.5 days**.
Task 5 gates on both `{2→3}` (ready day 3.0) and `{4}` (ready day 2.5), so it
starts at 3.0.

**Parallelism:** `{2→3}` runs alongside `4`; `6` and `7` run alongside `5`.

**Deliberate non-edges (do not "fix"):**
1. **Task 4 ∦ Task 2/3** — eval runner + `/orchestrate` baseline need neither
   guard nor manifests; the baseline is recorded against the pre-diet file.
2. **Tasks 6, 7, 7.5 ∦ Task 4** — only the pilot (`/orchestrate`, Task 5) is
   behaviorally evaled; the other diets are guard-verified only (D-12).
3. **Task 7.5 → Task 3** — the self-closing edge: Task 3's manifest
   computation reveals the residual start-load offenders 7.5 remediates.

Signed off: 2026-07-08

<!-- Component 7: Risk register -->

## 7. Risk register

Decision-domains gap check (merged catalog, 10 core domains, no overlay
additions): **no undecided catalogued domain.** secrets-config, dependency-
adoption, api-surface, observability, concurrency all fired and are decided
(knobs documented; no-dependency D-6; `check:instructions` task documented;
audit report is the signal with fail-loud manifest parsing per R2; hermetic
worktree eval runs). data-storage / caching / queues-async / auth /
deploy-migration are N/A. The two known catalog gaps (human-comprehension UX;
LLM eval gates) are logged observations, decided in-instance here.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | Diet drift — law changes meaning during a move. | REQ-D1.1 verbatim-in-meaning + `[manual]` PR review; `/orchestrate` pilot eval (Task 5) is the behavioral signal. |
| R2 | Manifest-parse silent miscount — unparseable entry underreports start-load, a real offender passes. | Guard + resolution check (REQ-B1.6) fail loud on unparseable manifests (D-5 anti-skip). Signal: Task 3 zero-missing-manifest gate. |
| R3 | spec-format exemption strands dependents — `/spec-draft` + `/spec-kickoff` start-load rests on Task 7.5's point-of-use reclassification, which must not defer gating law. | Task 7.5 coordinated with Task 7; a skill that can't reach budget without deferring gating law escalates a threshold-vs-safety tension. Signal: Task 3 start-load numbers. |
| R4 | Proxy failure — a skill under budget still degrades; only `/orchestrate` is evaled. | Accepted tradeoff (D-8 cost): one pilot backstop. Signal: the pilot's paired comparison. |
| R5 | Injected static/dynamic mis-split — REQ-A1.4 parser miscounts. | Warn-floor only (never fails CI), ~40-word surface, fixture-tested (REQ-A1.4). |
| R6 | Eval env — needs local Claude auth (never CI, D-8); worktree teardown can leave cruft. | Budget caps + teardown (D-6/Task 4); on-demand only. |
| R7 | Self-application — `instruction-hygiene.md` must pass the budget it defines while covering C1.1–C1.4. | Task 1 Done-when includes "under the doctrine per-file budget it defines." Signal: Task 1. |
| R8 | Eval-runner isolation & re-runnability — non-unique worktree names, crash-leftover cruft, intra-sweep races, eval hooks (`tasks-pr-sync`) mutating the primary checkout, baseline not bound to the pre-diet commit. | Task 4: unique worktree names + prune-first; disable project hooks inside eval runs; bind/verify the baseline to the pre-diet commit. (lens C1–C5) |
| R9 | Suppression-list merge contention — parallel diet PRs (5/6/7) each edit the shared list → conflict mis-resolution can strand or drop an allowance, mis-firing Task 8's gate. | Task 2/5/6/7: per-offender lines / merge-safe convention, or serialize list edits. (lens C6) |
| R10 | Guard performance — cache-free closure re-reads shared docs O(skills×docs); a resolver/config subprocess per reference. | Task 2: memoize per-file counts, batch config/resolver reads. (lens P1–P3) |
| R11 | Eval aggregate cost/runtime unbounded — per-run caps but no suite ceiling; grader calls ~double the API surface; pass^k early-exit unspecified. | Task 4: suite-level budget/turn cap; define early-exit. (lens P4–P6) |
| R12 | Eval failure-mode dispositions — budget-cap-hit, teardown failure, malformed cost JSON, aborted run in the pass^k tally all undefined. | Task 4 defines each fail-closed (the eval-side analogue of REQ-B1.8's guard fail-loud). (lens E16–E19) |

No open questions: every catalogued domain the spec touches is decided. R8–R12
were surfaced by the sign-off lens pass and deferred to execution as risk rows
(the sharp guard/eval-safety findings were folded into REQ-B1.8/B1.9/C1.6
instead — see §8).

Signed off: 2026-07-08

### Execution research log (appended by /execute-task; not part of the signed contract)

- **Task 1 (2026-07-09) — manifest grammar design.** D-3 delegates the exact
  manifest syntax to the doctrine doc. Chosen: a reserved column-zero line
  prefix (`Doctrine: <class> <doc-name>`), one entry per line, outside code
  fences, optional parenthesized site note on point-of-use entries.
  Considered: (a) a fenced block with an info string — rejected, D-3 requires
  entries *outside* fences so quoted examples stay inert; (b) HTML-comment
  markers — rejected, the manifest also feeds the skill's reading model and
  belongs in the visible prose; (c) multi-doc lines — rejected, per-line
  entries give REQ-B1.8's fail-loud a clean per-entry hook and cleaner diffs.
  The reserved prefix closes the grammar (any `Doctrine:` line must parse or
  is a guard error, satisfying REQ-B1.8); duplicate or dual-class doc names
  are malformed; doc names reuse the resolution chain's
  `^[a-z0-9][a-z0-9-]*$` identifier discipline (REQ-B1.6, REQ-B1.9 — the name
  is validated before any path is formed). Precedents consulted: the repo's
  `Planwright-Task:` trailer and `GATE(when:)` closed grammar; Anthropic
  skill-authoring guidance (progressive disclosure, one-level-deep
  references) per D-9/D-11's session survey.

<!-- Component 8: Sign-off -->

## 8. Sign-off

**Class:** meaning (first activation; additions count as meaning-class).

### Lens review pass (Discovery-Rigor, full bundle, first activation)

**Method:** parallel fan-out — 8 read-only sub-agents across the 9 canonical
lenses (performance + concurrency paired). Tool-grounded first:
`spec-validate` 0/0, `check-doc-links` all resolve, `markdownlint` 0. The spec
itself was the artifact under review (D-45: spec bugs are invisible to
execution feedback).

**Headline:** the fan-out caught a genuine **blocker in this walk's own Task-7.5
edit** — four independent lenses (correctness, error-handling, doc/format,
cross-file) converged on an interlocking deadlock (non-exemptible start-load +
a downstream-only fix gating every upstream green-check) plus an arithmetic
error in the spec-format coupling and a closure/mechanism mismatch. Redesigned
(Approach A) and re-traced to confirm the deadlock is broken.

**Lens-coverage table:**

| Lens | Findings (raw → disposition) | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 8 → 6 blocker + 2 | 6 fed the Task-7.5 blocker cluster; boundary-semantics → REQ-B1.8; floor-grounding = §4 note |
| Security | 8 → 6 | no secrets in prose; S5→REQ-A1.4, S3/S4/S8→REQ-B1.9, S1/S2/S6→REQ-C1.6; S7 = R8 |
| Error handling / failure modes | 21 → 1 principle + defers | fail-loud principle → REQ-B1.8; eval-side modes → R12; rest folded/deferred |
| Performance | 6 → deferred | R10, R11 |
| Concurrency / state | 10 → deferred | R8 (C1–C5), R9 (C6); C10 non-defect |
| Naming, readability, structure | 8 → applied | terminology normalized, `start-load`↔`mandatory-at-start` alias, warn-floor spelling unified |
| Documentation / format | 4 → applied | injected-context under-spec → REQ-A1.4; blocker → redesign; format compliant |
| Tests / verification | 6 → applied | A1.4↔B1.7 reconciled; D1.2/D1.4 tag overclaims fixed; "18 of 23" confirmed |
| Cross-file consistency | 4 → applied | stragglers fixed (C1.2 range, Task-2 over-correction); citations clean |

**Dispositions (all findings dispositioned — the refusal rule is satisfied):**

- **Applied as spec edits:** blocker redesign (Approach A — transitional
  `pending diet` allowance for start-load, seeded at Task 3, liquidated by
  7.5, forbidden at Task 8; arithmetic coupling corrected; Task 7.5 scoped to
  start-load); REQ-A1.4 fully specified (registered-hook discovery, static
  extraction rule, never-executed); REQ-B1.7 reconciled (row always, warn
  above floor); **new** REQ-B1.8 (fail-loud + boundary), REQ-B1.9
  (untrusted-input safety), REQ-C1.6 (eval artifact hygiene + evals-never-in-CI
  standing guard); D1.2/D1.4 test-tag overclaims corrected; terminology/naming
  cleanup; cross-file stragglers.
- **Deferred to risk register (execution owns):** R8 eval-runner isolation
  (C1–C5, S7), R9 suppression-list merge contention (C6), R10 guard perf
  (P1–P3), R11 eval aggregate cost (P4–P6), R12 eval failure-mode dispositions
  (E16–E19).
- **Non-defects / dropped:** C10 (check path is concurrent-safe), T#6 (C1.1
  `[design-level]` under-claim, not an overclaim), minor label nits (fixed
  inline).

Validator re-run after all applied edits: `0 error(s), 0 warning(s)`; 23 REQs,
full bidirectional REQ↔test-spec coverage; markdownlint 0; links resolve.

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-07-09.
Anchor: `00964548b7ca20d42f55bc8486ea1bca9a084491` — computed as
`scripts/spec-anchor.sh specs/prompt-hygiene`

### Amendment 1 (2026-07-09) — independent-model panel pass

**Class:** meaning (amendment; supersedes the anchor above).

An independent-model panel pass (`/panel-pairing`, gemini backend) ran after
kickoff to catch what the same-session Discovery-Rigor lens might have missed,
focused on the redesigned Task 7.5 / REQ-B1.3 transitional-allowance mechanism
and the sign-off additions (REQ-A1.4/B1.7/B1.8/B1.9/C1.6). It returned five
cross-file / interaction findings, none in the start-load fix itself (that
redesign's arithmetic and dependency graph were independently re-derived and
hold). All five were validated (three-pass) as real and accepted by the human
as meaning-class amendments:

- **F1 (deadlock, Needs human judgment → accepted):** Task 2 wires the guard
  into `mise run check` before Task 3 adds manifests, yet test-spec REQ-A1.2 /
  Task 3 treated an absent manifest as a hard error → Task 2 deadlocks Task 3.
  Fix (Option 1): a skill declaring **no** manifest scores start-load body-only
  (not an error); the hard missing-manifest error is reserved for a *malformed*
  manifest (REQ-A1.2, REQ-B1.8); a manifest-completeness assertion (wired at
  Task 3) guards silent under-report; test-spec REQ-A1.2 + Task 3 wording fixed.
- **F2 (asymmetry, Needs human judgment → accepted):** the transitional
  `pending diet` allowance covered per-file and start-load but not
  reachable-closure — the isomorphic deadlock the redesign fixed for start-load,
  left open for closure. Fix: extend REQ-B1.3(b) to cover reachable-closure too
  (REQ-D1.4, Task 8, test-spec updated in lockstep).
- **F3 (proportionality, Needs human judgment → accepted):** REQ-B1.8 made an
  unextractable injected-context hook a hard error, contradicting D-13 / REQ-B1.7's
  never-fail surface. Fix: carve the injected-context hook out of B1.8's fail-loud
  (which now governs only the deterministic manifest/exemption/knob inputs); an
  unextractable hook is a parse-failure **warning** (REQ-B1.7).
- **F4 (Needs sign-off → accepted):** REQ-C1.6 / Task 4 "carry only graded
  outcome + cost" omitted the fixture identifier, which the D-7 paired
  before/after comparison needs. Fix: retain the per-fixture identifier.
- **F5 (Needs sign-off → accepted):** REQ-B1.7 "exceeds the floor" → "meets or
  exceeds the floor" (align with REQ-B1.8's `≥`).

Validator re-run after the amendment: `0 error(s), 0 warning(s)`; 23 REQs,
full bidirectional REQ↔test-spec coverage; markdownlint 0; links resolve.
`specs/_observations/opportunities.md` merge conflict with main resolved as a
union (all three log entries kept).

Class: meaning
Anchor: `3c669ae9526f929c0078bd150ca5344ded8a6a87` — computed as
`scripts/spec-anchor.sh specs/prompt-hygiene`
