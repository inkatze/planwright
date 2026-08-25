# Operator dialogue — Tasks

**Status:** Ready
**Last reviewed:** 2026-08-25
**Format-version:** 2
**Execution:** derived — see the status render

Tasks 1→2→3→4 chain on the doctrine-then-instantiation order (the kickoff
instantiation cites the disciplines the doctrine defines, and calibration
refines the instantiation). Task 5 (the eval harness) is independent test
infrastructure and can dispatch early in parallel; Task 6 (acceptance) is the
join, needing the instantiated kickoff, the calibration, and the harness.
The 2026-08-24 extension adds a second lane with the same shape: Task 7
(arbitration doctrine) roots it, Task 8 follows, Tasks 9–10 fan out on 7 and
Tasks 11–12 on 7+8, and Task 13 (acceptance) is that lane's join over 9–12.

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
  shape (decisions first, counts over audit tables, full record one request
  away), the qualitative density bound (one decision cluster per turn,
  identifiers only where traceability needs them — stated as an extension of
  the shipped Small-bites rule, not a new mint), the no-monotonic-summary
  rule (running summaries become delta-plus-open, superseding the
  "cumulative" wording), and the self-containment-as-floor
  clarification; the colliding sentences in `discovery-rigor` (lens table and
  no-silent-pruning scoped to artifacts), `finding-categorization` (the
  in-turn composed presentation of the four tables given a declared side),
  and `gate-wiring`
  (the loop-end handoff's turn-side half declared and bounded) are amended to
  cite the arbitration; every emit mandate the task's edits touch declares
  its destination side.
- **Done when:** the arbitration, projection, density, and summary rules
  are stated in `doctrine/interaction-style.md`; the three colliding docs
  declare sidedness at the emit mandates this task touches and cite the
  arbitration; `mise run check:instructions` and `mise run check` are green.
- **Dependencies:** none
- **Citations:** D-14, D-15, D-20, D-21 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-I1.5, REQ-J1.3
- **Estimated effort:** 1 day

### Task 8 — Capture-at-birth in doctrine

- **Deliverables:** The capture rule landed in `doctrine/interaction-style.md`
  (the doc every attended surface already loads, per the kickoff §6 decision):
  an attended skill records dialogue-born action items in tracked state in
  the birth turn on the operator's confirmation (Awaiting-input or gated
  Deferred reference bullet, or observation fragment, as human-owned payload
  writes; task blocks via the amendment ritual only; no owning spec → the
  observations log; the companion bundle's ledger once it ships), proposes
  the tracked form itself, keeps a session-visible open-captures list shown
  at phase boundaries and on request in delta-plus-open form, and out-of-band
  fixes always carry a ship-gate record; the ship-gate rule added to
  `/spec-kickoff`'s lens-pass checklist items (the item: any out-of-band fix
  named in the walked bundle carries a tracked ship-gate record).
- **Done when:** `doctrine/interaction-style.md` states the
  confirm-then-write capture rule, the pre-ledger target list, the
  propose-the-form rule, the open-captures-list rule, the ship-gate rule, and
  the ledger-interface note (targets move to the action-item ledger when its
  owning bundle ships it); `/spec-kickoff`'s lens-pass checklist carries the
  ship-gate item; `mise run check:instructions` and `mise run check` are
  green.
- **Dependencies:** 7
- **Citations:** D-18 · REQ-L1.1, REQ-L1.2, REQ-L1.3, REQ-L1.4, REQ-L1.5
- **Estimated effort:** half day

### Task 9 — Repair the review-loop handoff family

- **Deliverables:** The gate-wiring loop-end handoff's turn-side emission
  declared and reworked to the projection (counts plus pending sign-offs and
  open forks, the residue itself projected; the four tables, declined log,
  and checklist stay artifact-side in full); `/self-review`, `/execute-task`
  (including the attended CI-failure surface, whose operator-facing rendering
  becomes excerpt-plus-pointer to the Awaiting-input record), and `/builder`
  conform, with each repaired surface's prose stating its per-skill
  instantiation (the sweep's per-skill instances repaired, not only the
  shared doc), mirroring its turn-side emission into the structured log's
  turn records (D-19), and `/execute-task` gaining its `interaction-style`
  manifest citation (its file is this task's; Task 11 covers the other three
  execution surfaces); `/polish` writes its accumulated audit record to
  `<worktree>/.claude/polish-audit.md` per D-16 (including the `.gitignore`
  entry) and projects turn-side, including at safety stops, with the nested
  return a projection plus the file pointer and the parent folding the full
  record into the PR body.
- **Done when:** the four skills and `gate-wiring` state the projection
  turn-side and the full-record artifact-side; `/polish` produces
  `.claude/polish-audit.md` on a standalone run and the `.gitignore` entry
  exists; `/execute-task`'s manifest cites `interaction-style`;
  `mise run check:instructions` and `mise run check` are green.
- **Dependencies:** 7
- **Citations:** D-15, D-16 · REQ-J1.1, REQ-J1.2, REQ-J1.5
- **Estimated effort:** 2 days

### Task 10 — Repair the authoring surfaces

- **Deliverables:** `/spec-draft`'s running summary converted to
  delta-plus-open and its phase-6 read-through converted to a projection
  (bounded excerpt plus the bundle as the artifact; self-critique dispositions
  as counts plus open questions); `/spec-kickoff`'s resume path confirms
  signed sections at one line each, its lens-coverage table emission declares
  the artifact side (recorded in full in the brief section, counts plus
  notable rows in the turn), and its handoff report becomes a projection
  (counts plus the actionable residue; the full report in the brief or PR
  body); both skills mirror their turn-side emissions into the structured
  log's turn records (D-19).
- **Done when:** both skills' prose states each converted form above and
  cites the arbitration; `mise run check:instructions` and `mise run check`
  are green.
- **Dependencies:** 7
- **Citations:** D-15, D-21 · REQ-J1.1, REQ-J1.3, REQ-J1.5
- **Estimated effort:** 1 day

### Task 11 — Execution-surface instantiation pass

- **Deliverables:** The disciplines and the arbitration instantiated at
  `/orchestrate`, `/resume`, and `/drain`, each gaining its
  `interaction-style` manifest citation (`/execute-task`'s file is Task 9's,
  which carries its citation; this task also widens
  `scripts/check-doctrine-manifest.sh`'s surface list to all four
  execution-side surfaces, test-spec REQ-K1.1): `/orchestrate` gets the
  defined step report (state / reasoning / requests slots, open
  decision-shaped content routed through capture), bounded
  actionability-ordered batched halts, and the watch-loop attention render
  converted to render-on-transition (or bounded delta, with the periodic
  liveness line REQ-K1.3 permits) — amending the `orchestration-modes`
  render-each-iteration mandate and adding the script-level unit test for the
  skip-on-no-change path; `/resume` leads with its question plus a
  compact status line, the seven context elements on request; `/drain`
  reports counts per lane with detail on request, generalizing its existing
  single-lane pattern; the three surfaces mirror their turn-side emissions
  into the structured log's turn records (D-19).
- **Done when:** the three skills instantiate the disciplines and cite the
  doctrine in their manifests and `check:doctrine-manifest` covers and passes
  on all four execution-side surfaces; the step report's slot structure is
  stated in `/orchestrate`'s prose; the render-on-transition unit test exists
  and passes in `mise run check`; `mise run check:instructions` and
  `mise run check` are green.
- **Dependencies:** 7, 8
- **Citations:** D-13, D-17, D-15, D-9 · REQ-K1.1, REQ-K1.2, REQ-K1.3, REQ-J1.4, REQ-L1.3, REQ-A1.3
- **Estimated effort:** 2 days

### Task 12 — Turn-shape enforcement: eval invariants and the sidedness check

- **Deliverables:** The behavioral eval harness extended with turn-shape
  invariants graded from the structured decision/transcript log's new turn
  records (the additive schema bump D-19 specifies): no turn-side
  multi-table dump, projection present, decisions-first ordering, no
  monotonic summary growth, bounded selector identifier density (numeric
  values in fixtures, not doctrine), and the capture-at-birth assertion (a
  planted, operator-confirmed action item exists in tracked state — mirrored
  into the graded artifacts — by run end); every fixture the extension's
  test-spec entries name, authored here (the wall and projection pair, the
  review-loop and `/polish`-standalone fixtures, the CI-failure fixture, the
  `/resume`, `/drain`, and multi-halt orchestrate fixtures, the multi-phase
  and resumed-kickoff fixtures), with pass thresholds pinned in fixtures
  (personas × runs; a flake is a failure); plus the static
  advisory sidedness check flagging emit mandates with no declared destination
  side, wired into `mise run check` reporting-only (always exit zero), its
  deliberately side-less-mandate fixture living under `tests/`, outside the
  scanned corpus, with a unit test for the check's own detection; the new
  invariants registered under the `eval:` namespace `check-no-ci-evals.sh`
  covers.
- **Done when:** each invariant runs against its fixture pair and pass/fail
  correctly (the wall-class fixture fails it, the conforming fixture passes
  it); the sidedness check reports the planted fixture in its unit test and
  exits zero in `mise run check`; `check-no-ci-evals.sh` passes with the new
  invariants registered under `eval:`; `mise run check` is green.
- **Dependencies:** 7, 8
- **Citations:** D-19 · REQ-M1.1, REQ-M1.3, REQ-M1.4
- **Estimated effort:** 2 days

### Task 13 — Acceptance join: invariants against the repaired surfaces

- **Deliverables:** The turn-shape invariants run against the repaired
  surfaces — a kickoff run and at least one execution-side surface run, the
  acceptance sample this task's Done-when binds to — reusing the base
  bundle's novice/expert personas (extended as fixtures where the base
  stub's turn-indexed answers do not fit); the extension's test-spec entries
  reworded from planned voice to describe their now-runnable paths, with a
  dated changelog entry recording the flip; a small repair the invariants
  catch out is fixed in this task, and a structural miss is recorded as a
  disposition that reopens the owning repair task rather than absorbed here;
  the experiential rubric record appended to the kickoff brief.
- **Done when:** the eval passes against the sampled kickoff and
  execution-side runs under both personas; the rubric pass is recorded in
  the brief with the human as final rater; the test-spec rewording and its
  changelog entry are on disk; `mise run check` is green.
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
- **Standing turn-shape eval cadence.** Beyond Task 13's acceptance run the
  eval stays on-demand (REQ-M1.4); whether a standing trigger is warranted —
  the recommended shape being an on-demand run before merging prose changes
  to attended surfaces — is decided on post-acceptance evidence rather than
  legislated now. Confidence: medium. **Gate:** after Task 13 completes and
  attended-surface prose changes have merged post-acceptance, so the decision
  rests on observed drift rather than prediction. Citations: D-19; REQ-M1.4;
  extension kickoff lens-pass cluster F (2026-08-24).

## Out of scope

- Any weakening of the reserved human controls (never-auto-merge, never
  auto-chain, draft-PR-only, the two-key launch, the sign-off record and
  content anchor). Permanent.
- Any verdict, score, or quality assessment of a spec produced by a skill on
  its own behalf. Permanent (the independence firewall).
- Wiring the behavioral evals into CI or `mise run check`. Permanent; evals are
  on-demand by design.
