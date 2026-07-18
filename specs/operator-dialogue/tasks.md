# Operator dialogue — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-17
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
- **Execution-side handoffs pass.** Extending the doctrine's instantiation to
  `/orchestrate`, `/execute-task`, `/resume`, and `/drain` (their handoffs,
  reports, and disposition prompts). This pass also adds the `interaction-style`
  manifest citation to those four surfaces (REQ-A1.3), deferred with the behavior
  it promises rather than cited ahead of it. Confidence: high. **Gate:** after
  the kickoff instantiation proves the doctrine and the eval loop on one surface.
  Citations: D-9.

## Out of scope

- Any weakening of the reserved human controls (never-auto-merge, never
  auto-chain, draft-PR-only, the two-key launch, the sign-off record and
  content anchor). Permanent.
- Any verdict, score, or quality assessment of a spec produced by a skill on
  its own behalf. Permanent (the independence firewall).
- Wiring the behavioral evals into CI or `mise run check`. Permanent; evals are
  on-demand by design.
