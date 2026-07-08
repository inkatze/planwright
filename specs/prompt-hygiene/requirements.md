# Prompt Hygiene — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-08
**Format-version:** 1

## Goal

planwright's instruction files, the `SKILL.md` bodies the harness loads at
invocation and the `doctrine/*.md` rule docs skills front-load at run start,
grow monotonically as features land, and instruction-following measurably
degrades as instruction context bloats. Nothing today measures or bounds
this: `/orchestrate` is ~6,900 words (the official skill-authoring ceiling is
500 lines, roughly 4,250 words at this corpus's density), and a single skill
invocation can pull 12k+ words of instructions into context before any work
begins. This spec (a) measures the problem: an audit ranking every
instruction file and every skill's per-invocation instruction load; and (b)
installs standing mechanisms so bloat cannot recur silently: a size-budget
guard in `mise run check`, an authoring doctrine rule making progressive
disclosure the norm (skills carry the flow; rule docs carry the law; bulk
and rare branches load at point of use, never at run start), and executed
diets bringing the worst offenders under budget, with one diet verified
behaviorally through a kept regression eval. Size and load are the
enforceable proxies; semantic quality stays review-time judgment.

## Scope

### In scope

- A measurement/audit tool: per-file word counts, per-skill
  mandatory-at-start load and reachable closure, ranked report, offender
  shortlist with a diet plan per offender.
- A size-budget CI guard wired into the `mise run check` aggregate, with
  overlay-tunable threshold knobs, a recorded-reason exemption mechanism,
  and a deterministic rule-doc resolution check.
- An authoring doctrine rule doc (`doctrine/instruction-hygiene.md`):
  progressive disclosure, the doctrine-manifest convention, the
  always-loaded-core vs point-of-use loading convention, the
  test-and-measure principle, and the kept prompt-eval convention.
- Executed diets on the shortlisted offenders, including on-demand loading
  restructuring, with behavior preserved.
- A kept prompt-regression eval format plus a pilot: one dieted skill
  verified before/after with recorded results.
- A guard-catalog entry so the builder recommends instruction hygiene to
  adopters.

### Out of scope

- Pipeline output artifacts (PR bodies, accumulators, generated views):
  `specs/output-hygiene`'s domain. This spec governs the instruction side
  only; the two specs share a family boundary, not a fold.
- Semantic-quality enforcement in CI. A file can be long and structured or
  short and muddled; quality stays a review-time judgment.
- Runtime session-context management (`context_budget_threshold` and the
  auto-heal machinery): `specs/orchestration-fleet`'s layer.
- Human-facing documentation (`docs/*.md`, `README.md`): read by people,
  not loaded as model instructions.
- Spec bundles under `specs/`: content the pipeline processes, not
  instructions that drive it.
- Per-commit CI execution of behavioral evals (cost, nondeterminism, and
  an API-key requirement in shared CI). Evals are kept and run on demand.
- Adopting an eval framework (promptfoo, DeepEval, Braintrust, Inspect) or
  any new runtime dependency for the eval runner.
- A full instruction drift lint (stale statuses, knobs, IDs in skill
  prose): deferred with a recurrence gate in `tasks.md`.
- A section-scoped resolver mode (loading one section of a rule doc):
  deferred in `tasks.md`.

## REQ-A — Measurement & audit

- **REQ-A1.1** A measurement tool SHALL compute word counts (with line
  counts reported informationally) for every instruction file
  (`skills/*/SKILL.md`, `doctrine/*.md`) and emit a ranked report.
  *(Cites: the invocation seed (Sources), D-2.)*
- **REQ-A1.2** The tool SHALL compute, per skill, the mandatory-at-start
  load (the SKILL.md plus the rule docs its manifest requires at run start)
  and the reachable closure (plus every rule doc the manifest defers to
  point of use), derived mechanically from the skill's doctrine manifest.
  *(Cites: D-1, D-3.)*
- **REQ-A1.3** The audit SHALL produce a ranked offender shortlist with a
  diet plan per shortlisted file naming what moves to rule docs, what
  collapses to a reference, what is cut, and what defers to point-of-use
  loading.
  *(Cites: the invocation seed (Sources), drafting-session decision (2026-07-08).)*

## REQ-B — Instruction guard

- **REQ-B1.1** A size-budget check SHALL be wired into the `mise run check`
  aggregate like the sibling guards: error-threshold violations fail the
  check; warn-threshold violations are reported without failing.
  *(Cites: the invocation seed (Sources), D-4.)*
- **REQ-B1.2** The guard SHALL enforce per-file floors, a tight
  mandatory-at-start budget, and a loose reachable-closure budget; every
  threshold SHALL be a config knob with its default in
  `config/defaults.yml`, overlay-tunable per the customization boundary.
  *(Cites: D-1, D-5.)*
- **REQ-B1.3** The guard SHALL support an exemption mechanism naming the
  exempt file and a recorded reason; an exemption SHALL suppress only that
  file's per-file floor, never the start-load or closure budgets, and an
  exemption without a reason SHALL be an error.
  *(Cites: D-5.)*
- **REQ-B1.4** Every config knob this spec introduces SHALL have a row in
  `docs/options-reference.md`.
  *(Cites: bootstrap D-43.)*
- **REQ-B1.5** Default thresholds SHALL be grounded: derived from the
  published skill-authoring guidance (the 500-line SKILL.md ceiling) and
  the measured corpus distribution, with the derivation recorded as a
  design decision.
  *(Cites: D-2, research: Anthropic skill-authoring best practices.)*
- **REQ-B1.6** A deterministic resolution check SHALL verify that every
  rule-doc reference a skill's doctrine manifest relies on, run-start and
  point-of-use alike, resolves through the rule-doc resolution chain; an
  unresolvable reference SHALL fail the check.
  *(Cites: D-3, drafting-session decision (2026-07-08).)*

## REQ-C — Authoring doctrine

- **REQ-C1.1** A doctrine rule doc SHALL define the instruction-authoring
  rule: the SKILL.md carries the flow; normative law lives in rule docs
  referenced by resolution path; references stay one level deep from the
  SKILL.md.
  *(Cites: the invocation seed (Sources), D-9, D-10.)*
- **REQ-C1.2** The rule doc SHALL define the loading convention: an
  always-loaded core (hard invariants and any law that gates whether an
  action is permitted, which SHALL NOT be deferred) versus deferred bulk
  read at point of use.
  *(Cites: D-9.)*
- **REQ-C1.3** The rule doc SHALL state the test-and-measure principle:
  instruction files are runtime artifacts; nondeterminism changes the form
  and cadence of verification, never whether to verify.
  *(Cites: drafting-session decision (2026-07-08).)*
- **REQ-C1.4** The rule doc SHALL define the kept prompt-eval convention:
  the fixture format, the dependency-free runner contract, pass^k gating
  (default k=3, never gating on a single run), on-change/on-demand cadence,
  and per-run cost capture.
  *(Cites: D-6, D-7, D-8.)*
- **REQ-C1.5** The guard catalog SHALL gain an instruction-hygiene entry so
  the builder can recommend the guard and the eval convention to adopters.
  *(Cites: D-10, drafting-session decision (2026-07-08).)*

## REQ-D — Diets & verification

- **REQ-D1.1** Each shortlisted offender SHALL be slimmed per its diet plan
  until it passes the guard; moved law SHALL be relocated verbatim in
  meaning (no contract change rides a diet).
  *(Cites: the invocation seed (Sources), D-5.)*
- **REQ-D1.2** Law moved out of a skill SHALL land in a resolved rule doc,
  with the skill retaining a resolution-path reference recorded in its
  doctrine manifest.
  *(Cites: D-3, REQ-B1.6.)*
- **REQ-D1.3** One dieted skill SHALL be verified behaviorally: a kept
  before/after eval (baseline recorded against the pre-diet file, the same
  fixtures re-run post-diet), gated pass^k with paired comparison, results
  and cost recorded.
  *(Cites: D-7, D-12.)*
- **REQ-D1.4** After the diets, the guard SHALL pass with zero grandfathered
  errors: the exemption list carries only permanent recorded exemptions,
  with no `pending diet` entries remaining.
  *(Cites: drafting-session decision (2026-07-08).)*

## Changelog

- 2026-07-08 — Bundle drafted via `/spec-draft` (fold-detection ran against
  all nine non-terminal bundles; overlap with `specs/output-hygiene` judged
  a family boundary, spin-new triggers fired; zero observations-log entries
  consumed).

## Sources

- **The invocation seed** — operator idea captured 2026-07-08 during the
  `specs/inception` drafting session: instruction files have grown long,
  instruction-following degrades with prompt bloat; candidate mechanisms
  (CI size budget, authoring doctrine, initial audit, size-as-proxy
  decision) supplied for evaluation.
- **Anthropic skill-authoring best practices** — official guidance
  (`platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices`):
  the 500-line SKILL.md ceiling, progressive-disclosure patterns,
  one-level-deep references, evaluation-first authoring, and the note that
  no built-in eval runner exists.
- **Prompt-eval tooling & degradation research survey** — session research
  (2026-07-08, primary sources verified): the skill-creator eval convention
  (prose workflow plus schemas, no shipped end-to-end runner), headless
  `claude -p` mechanics for hermetic runs, framework landscape (promptfoo
  claude-agent-sdk and `exec:` providers, Inspect `claude_code()`),
  pass^k discipline (tau-bench arXiv 2406.12045; Anthropic "Demystifying
  evals for AI agents"), and the degradation citation set (NoLiMa arXiv
  2502.05167; ManyIFEval arXiv 2509.21051; IFScale arXiv 2507.11538;
  Chroma "Context Rot"; Anthropic "Effective context engineering for AI
  agents").
