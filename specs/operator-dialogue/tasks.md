# Operator dialogue — Tasks

**Status:** Draft
**Last reviewed:** 2026-08-24
**Format-version:** 2
**Execution:** derived — see the status render

Tasks 1→2→3→4 chain on the doctrine-then-instantiation order (the kickoff
instantiation cites the disciplines the doctrine defines, and calibration
refines the instantiation). Task 5 (the eval harness) is independent test
infrastructure and can dispatch early in parallel; Task 6 (acceptance) is the
join, needing the instantiated kickoff, the calibration, and the harness.

## Tasks

### Task 1 — Rework the `interaction-style` doctrine

- **Deliverables:** `doctrine/interaction-style.md` widened to govern every
  attended human surface (not only the two authoring skills) and given the
  three named disciplines — teach to the frontier, interview to completeness,
  present without steering — each stated as inspectable rules, including the
  information-versus-advice line with its escape valve and the IPDAS-style
  balance rules; prose kept terse and point-of-use so front-loading skills stay
  within their start-load budgets.
- **Done when:** `doctrine/interaction-style.md` states the widened scope and
  the three disciplines with the no-verdict/escape-valve and balance rules;
  `check:instructions` passes on every skill that front-loads the doc;
  `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-1, D-3, D-4, D-5, D-6, D-10, D-12 · REQ-A1.1, REQ-A1.2, REQ-A1.4, REQ-B1.3, REQ-C1.1, REQ-C1.3, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5
- **Estimated effort:** 1 day

### Task 2 — Self-contained-confirmation rule and structural check

- **Deliverables:** The self-contained-confirmation rule added to the doctrine
  (each option restates its action and consequence; explicit equal-weight
  reject; no pre-selected default; no OK/Yes/No; deeper detail supplementary,
  never load-bearing), plus a reusable structural check that asserts a
  confirmation option set is self-contained and carries a reject option with no
  default.
- **Done when:** the rule is documented in `doctrine/interaction-style.md`; the
  structural check exists, is unit-tested, and flags a non-self-contained or
  defaulted confirmation; `mise run check` is green.
- **Dependencies:** 1
- **Citations:** D-7 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-H1.2
- **Estimated effort:** half day

### Task 3 — Instantiate the disciplines at `/spec-kickoff`

- **Deliverables:** `skills/spec-kickoff/SKILL.md` reworked so the guided
  dialogue and sign-off instantiate the three disciplines in-band: comprehend
  the spec faithfully first; run the completeness interview (backward-chaining
  over the bundle's dependency structure, bounded per pass); present
  non-directively; replace the bare verdict-demand gate with a compact
  "here is what you are about to approve and what changes downstream" summary;
  frame the mechanical gates (lens pass, anchor, CI) in plain language as what
  they protect; and emit a structured decision/transcript log for grading. All
  within the instruction budget and reconciled with `skill-rigor`'s in-flight
  sign-off changes.
- **Done when:** `skills/spec-kickoff/SKILL.md` reflects the instantiation and
  the structured-log emit; the existing invariants (never-auto-merge, two-key
  launch, no-auto-chain, draft-PR-only, sign-off record + anchor) are intact;
  `check:instructions` passes on the kickoff surface; `mise run check` is green.
- **Dependencies:** 1, 2
- **Citations:** D-2, D-3, D-5, D-9, D-10 · REQ-B1.1, REQ-B1.2, REQ-B1.5, REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4, REQ-F1.5, REQ-G1.3
- **Estimated effort:** 2 days

### Task 4 — Adaptive-level calibration in the kickoff dialogue

- **Deliverables:** The frontier-and-fade calibration wired into
  `/spec-kickoff`: a lightweight running per-concept estimate of the operator's
  uptake drives explanation depth (skip what the operator demonstrably holds,
  teach the gap, fade scaffolding across sections), with no heavyweight learner
  model.
- **Done when:** `skills/spec-kickoff/SKILL.md` documents the calibration
  behavior (frontier detection, fade, the lightweight estimate, the no-model
  bound); `check:instructions` passes; `mise run check` is green.
- **Dependencies:** 3
- **Citations:** D-4 · REQ-B1.3, REQ-B1.4
- **Estimated effort:** 1 day

### Task 5 — Behavioral eval harness scaffold

- **Deliverables:** An on-demand behavioral eval that drives a skill through a
  real interactive TTY session (a tmux window driven by `send-keys` + `C-m`,
  idle detected by positive footer anchor), answered by a simulated-operator
  driver parameterized by expertise persona (at minimum novice and expert);
  grading reads the durable artifacts the run writes, never a scraped pane;
  an independent-grader hook (a non-Anthropic panel backend and/or human final
  rater); reusing the prompt-eval isolation and hygiene disciplines (disposable
  per-run worktree, budget caps, fail-closed teardown, allowlisted scalar-only
  results); on-demand only, never wired into CI. The scaffold demonstrates
  against a generic fixture skill; the acceptance assertions that drive the real
  `/spec-kickoff` surface live in Task 6. The harness honors the REQ-G1.6
  security disciplines: persona text sanitized before `send-keys`,
  containment-checked worktree teardown, escape-safe structured log, echo-safety
  on surfaced artifact values, fixture-only content to any third-party grader,
  grader-backend credentials from the environment/secret store (never committed or
  recorded), the kickoff driven with publishing disabled (no push / PR / ready
  flip), and eval-only marking of any driver-produced sign-off record; plus the
  REQ-G1.5 isolation additions (per-run-unique `tmux` window name, stale-window
  reaping).
- **Done when:** the harness runs a persona-driven session end-to-end against a
  fixture skill and emits an artifact-graded result; the harness is registered
  under the `eval:` task namespace so `scripts/check-no-ci-evals.sh` covers it
  and still passes (the harness is not in CI); `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-8 · REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-G1.5, REQ-G1.6
- **Estimated effort:** 3 days

### Task 6 — Kickoff acceptance: invariants, persona pilots, rubric self-audit

- **Deliverables:** The measurable-acceptance layer wired: the assertable
  `[test]` invariant checks over a kickoff run (self-contained option set via
  Task 2's check, absence of verdict tokens, preserved normative tokens,
  completeness — no readiness while a required decision is undefined); the
  additional assertable checks and their fixtures — the REQ-A1.3 manifest-grep
  check, the REQ-C1.1 completeness fixture (a known-required-but-undefined
  decision) and REQ-C1.2 changed-answer-reopens-dependents fixture, and the
  REQ-F1.2 sign-off-summary-emitted-before-decision assertion, and the REQ-C1.5
  input-robustness fixture (malformed input re-prompts and does not corrupt the
  calibration estimate); the persona pilots
  asserting the kickoff pitched differently and appropriately to a novice versus
  an expert operator; and the CDC Clear Communication Index and IPDAS balance
  rubrics wired as the experiential-quality instrument scored by the independent
  grader with the human as final rater (the rubric self-audit is a non-scoring
  diagnostic pre-pass, per REQ-H1.3).
- **Done when:** the invariant checks (including the A1.3 grep, the C1.1/C1.2
  fixtures, and the F1.2 assertion) run against a kickoff eval fixture and pass;
  the novice/expert persona pilots produce a graded divergence in explanation
  depth; the rubric instrument and its diagnostic self-audit are documented and
  runnable; `mise run check` is green.
- **Dependencies:** 3, 4, 5
- **Citations:** D-11 · REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4, REQ-G1.2, REQ-A1.3, REQ-C1.1, REQ-C1.2, REQ-C1.5, REQ-F1.2
- **Estimated effort:** 2 days

### Task 7 — Arbitration and projection rules in doctrine

- **Deliverables:** The turn/artifact arbitration landed in doctrine:
  `interaction-style` gains the arbitration statement, the bounded-projection
  shape (decisions first, counts over tables, full record one request away),
  the qualitative density bound (one decision cluster per turn, identifiers
  only where traceability needs them), the no-monotonic-accumulator rule
  (running summaries become delta-plus-open), and the self-containment-as-floor
  clarification; the colliding sentences in `discovery-rigor` (lens table and
  no-silent-pruning scoped to artifacts), `finding-categorization` (the
  "present the four tables" sidedness ambiguity resolved), and `gate-wiring`
  (the loop-end handoff's turn-side half declared and bounded) are amended to
  cite the arbitration; every emit mandate touched declares its destination
  side.
- **Done when:** the arbitration, projection, density, and accumulator rules
  are stated in `doctrine/interaction-style.md`; the three colliding docs
  declare sidedness at their emit mandates and cite the arbitration;
  `check:instructions` passes on every skill front-loading the touched docs;
  `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-14, D-15, D-20, D-21 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-I1.5, REQ-J1.3
- **Estimated effort:** 1 day

### Task 8 — Capture-at-birth in doctrine

- **Deliverables:** The capture rule landed in doctrine: an attended skill
  records dialogue-born action items in tracked state at birth (task block,
  Awaiting-input, gated Deferred, or observation fragment; the companion
  bundle's ledger once it ships), proposes the tracked form itself, keeps a
  session-visible ledger shown at natural pauses, and out-of-band fixes always
  carry a ship-gate record; the ship-gate rule added to the kickoff lens-pass
  checklist items.
- **Done when:** the capture rules are stated in doctrine with the
  tracked-state target list and the ledger-interface note; the kickoff
  checklist carries the ship-gate item; `check:instructions` and
  `mise run check` are green.
- **Dependencies:** 7
- **Citations:** D-18 · REQ-L1.1, REQ-L1.2, REQ-L1.3, REQ-L1.4, REQ-L1.5
- **Estimated effort:** half day

### Task 9 — Repair the review-loop handoff family

- **Deliverables:** The gate-wiring loop-end handoff's turn-side emission
  reworked to the projection (counts plus pending sign-offs and open forks;
  the four tables, declined log, and checklist stay artifact-side in full);
  `/self-review`, `/execute-task` (including the attended CI-failure surface,
  which becomes excerpt-plus-pointer), and `/builder` conform; `/polish`
  writes its accumulated audit record to the worktree-local cache file beside
  the handover brief and projects turn-side, including at safety stops.
- **Done when:** the four skills and `gate-wiring` emit turn-side only the
  projection while their artifacts carry the full record; `/polish` produces
  the cache file on a standalone run; `check:instructions` passes on every
  touched surface; `mise run check` is green.
- **Dependencies:** 7
- **Citations:** D-15, D-16 · REQ-J1.1, REQ-J1.2, REQ-J1.5
- **Estimated effort:** 2 days

### Task 10 — Repair the authoring surfaces

- **Deliverables:** `/spec-draft`'s running summary converted to
  delta-plus-open and its phase-6 read-through converted to a projection
  (bounded excerpt plus the bundle as the artifact; self-critique dispositions
  as counts plus open questions); `/spec-kickoff`'s resume path confirms
  signed sections at one line each, its lens-coverage table emission declares
  the artifact side (recorded in the brief section, projected in the turn),
  and its nine-item handoff report becomes a projection.
- **Done when:** both skills' prose states the bounded forms and cites the
  arbitration; `check:instructions` passes on both; `mise run check` is green.
- **Dependencies:** 7
- **Citations:** D-15, D-21 · REQ-J1.1, REQ-J1.3, REQ-J1.5
- **Estimated effort:** 1 day

### Task 11 — Execution-surface instantiation pass

- **Deliverables:** The disciplines and the arbitration instantiated at the
  four execution-side surfaces, each gaining its `interaction-style` manifest
  citation: `/orchestrate` gets the defined step report (state / reasoning /
  requests slots, decision-shaped content routed through capture), bounded
  actionability-ordered batched halts, and render-on-change (or bounded-delta)
  for the fleet/watch surface; `/resume` leads with its question plus a
  compact status line, the seven context elements on request; `/drain`
  reports counts per lane with detail on request, generalizing its existing
  single-lane pattern.
- **Done when:** the four skills instantiate the disciplines and cite the
  doctrine in their manifests; the step report's slot structure is stated in
  `/orchestrate`'s prose; `check:instructions` passes on all four;
  `mise run check` is green.
- **Dependencies:** 7, 8
- **Citations:** D-13, D-17, D-15 · REQ-K1.1, REQ-K1.2, REQ-K1.3, REQ-J1.4, REQ-L1.3
- **Estimated effort:** 2 days

### Task 12 — Turn-shape enforcement: eval invariants and the sidedness check

- **Deliverables:** The behavioral eval harness extended with turn-shape
  invariants graded from the structured decision/transcript log: no turn-side
  multi-table dump, projection present, decisions-first ordering, no
  monotonic summary growth, bounded selector identifier density (numeric
  values in fixtures, not doctrine), and the capture-at-birth assertion (a
  planted action item exists in tracked state by run end); plus the static
  advisory sidedness check flagging emit mandates with no declared destination
  side, wired informational-only.
- **Done when:** the invariants run against an eval fixture and pass/fail
  correctly (a fixture wall fails, a fixture projection passes); the sidedness
  check runs and reports without gating; `check-no-ci-evals.sh` still passes
  with the extensions covered; `mise run check` is green.
- **Dependencies:** 7, 8
- **Citations:** D-19 · REQ-M1.1, REQ-M1.3, REQ-M1.4
- **Estimated effort:** 2 days

### Task 13 — Acceptance join: invariants against the repaired surfaces

- **Deliverables:** The turn-shape invariants run against the repaired
  surfaces (a kickoff run and at least one execution-side surface run),
  reusing the base bundle's novice/expert personas; the test-spec entries for
  the extension flipped from planned to verified paths; any repair the
  invariants catch out is fixed in the same task.
- **Done when:** the eval passes against the repaired surfaces under both
  personas; the experiential rubric pass is documented as run with the human
  as final rater; `mise run check` is green.
- **Dependencies:** 9, 10, 11, 12
- **Citations:** D-19, D-11 · REQ-M1.1, REQ-M1.2, REQ-J1.1
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **`/spec-walkthrough` revisit.** The walkthrough shipped out-of-band and
  on-demand-only and went unused; its fate (rethink or retire) is a scoped
  amendment to the Done `spec-comprehension` bundle, informed by the failure
  captured in this bundle's Sources, not a mechanical doctrine adoption.
  Confidence: medium. **Gate:** after this spec's kickoff instantiation
  (Tasks 3–4) has proven out, so the in-band model is validated before the
  walkthrough is re-decided against it. Citations: D-2, D-9; the spec-walkthrough
  failure (Sources).

## Out of scope

- Any weakening of the reserved human controls (never-auto-merge, never
  auto-chain, draft-PR-only, the two-key launch, the sign-off record and
  content anchor). Permanent.
- Any verdict, score, or quality assessment of a spec produced by a skill on
  its own behalf. Permanent (the independence firewall).
- Wiring the behavioral evals into CI or `mise run check`. Permanent; evals are
  on-demand by design.
