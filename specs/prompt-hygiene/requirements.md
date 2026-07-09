# Prompt Hygiene — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-09
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
  (`skills/*/SKILL.md`, `doctrine/*.md`) and emit a ranked report. The
  `doctrine/README.md` index SHALL be excluded from the per-file walk: it is
  an index, not run-start law, and no skill's manifest loads it.
  *(Cites: the invocation seed (Sources), D-2, kickoff §3 (2026-07-08).)*
- **REQ-A1.2** The tool SHALL compute, per skill, the mandatory-at-start
  load (the SKILL.md plus the rule docs its manifest requires at run start)
  and the reachable closure (plus every rule doc the manifest defers to
  point of use), derived mechanically from the skill's doctrine manifest. A
  skill that declares **no** manifest is not an error: its run-start set is
  empty, so its mandatory-at-start is scored as its SKILL.md body alone (the
  missing-manifest error is reserved for a *malformed* manifest, REQ-B1.8).
  Separately, the guard SHALL carry a **manifest-completeness assertion** —
  every `skills/*/SKILL.md` declares a doctrine manifest — so a manifest-less
  skill cannot silently under-report its start-load once manifests are the
  corpus norm; that assertion is wired in when the manifests land (Task 3),
  not before.
  *(Cites: D-1, D-3.)*
- **REQ-A1.3** The audit SHALL produce a ranked offender shortlist — files
  over their per-file floors **and** skills over the mandatory-at-start or
  reachable-closure budgets — with a diet plan per shortlisted offender
  naming what moves to rule docs, what collapses to a reference, what is cut,
  and what defers to point-of-use loading.
  *(Cites: the invocation seed (Sources), drafting-session decision (2026-07-08), kickoff §3 (2026-07-08).)*
- **REQ-A1.4** The audit SHALL identify injected-context hooks — the hooks
  registered in the plugin's `hooks.json` whose scripts emit
  `additionalContext` / `hookSpecificOutput` — and measure the **static**
  injected prose each contributes, reported as a distinct injected-context
  class in the ranked report. Discovery SHALL be over registered hooks, not
  an arbitrary file grep. Measurement SHALL be **static**: the hook script is
  read, never executed; a line containing a `$(…)` or `${…}` interpolation is
  excluded from the static count (its dynamic contribution is noted, not
  counted). Every identified injected-context hook SHALL appear as a row in
  the report (its warn state is REQ-B1.7's concern, not its presence).
  *(Cites: D-13, kickoff §3 (2026-07-08), kickoff sign-off lens pass (2026-07-09).)*

## REQ-B — Instruction guard

- **REQ-B1.1** A size-budget check SHALL be wired into the `mise run check`
  aggregate like the sibling guards: error-threshold violations fail the
  check; warn-threshold violations are reported without failing.
  *(Cites: the invocation seed (Sources), D-4.)*
- **REQ-B1.2** The guard SHALL enforce per-file floors, a tight
  mandatory-at-start budget (the *start-load*: SKILL.md plus run-start rule
  docs), and a loose reachable-closure budget (start-load plus point-of-use
  docs); every threshold SHALL be a config knob with its default in
  `config/defaults.yml`, overlay-tunable per the customization boundary.
  ("Start-load" and "mandatory-at-start" name the same budget throughout.)
  *(Cites: D-1, D-5.)*
- **REQ-B1.3** The guard SHALL support two distinct suppression forms, each
  naming its target and a recorded reason (a reason-less entry of either form
  SHALL be an error):
  (a) a **permanent exemption**, which suppresses only a file's per-file
  floor, **never** the mandatory-at-start or reachable-closure budgets, and
  carries a standing rationale; and
  (b) a **transitional `pending diet (Task N)` allowance**, which temporarily
  permits one named over-budget offender — per-file, mandatory-at-start, **or**
  reachable-closure — to not fail the check for the duration of its diet, is
  removed by that task's own PR, and SHALL be forbidden at closeout (REQ-D1.4).
  The transitional allowance is the only form that may cover a mandatory-at-start
  or reachable-closure offender, and only transiently; no permanent exemption
  ever suppresses the start-load or closure budgets. (Covering closure too is the
  symmetric deadlock fix: a closure offender the manifest computation surfaces
  needs a content diet no single task pre-scopes, and without a transitional
  escape it would deadlock the graph exactly as an unexemptible start-load
  offender once did.)
  *(Cites: D-5, kickoff sign-off lens pass (2026-07-09), amendment (2026-07-09).)*
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
- **REQ-B1.7** The injected static prose measured under REQ-A1.4 SHALL carry
  a warn-level floor only: an injected-context hook whose static prose meets or
  exceeds the floor SHALL be reported as a warning, and SHALL NOT fail the check
  (the surface is per-session and partly dynamic). The floor gates only the
  warning, never the report row (which REQ-A1.4 always emits). An injected-context
  hook whose static prose the guard cannot extract SHALL likewise be reported as a
  warning (a parse-failure warning), never a hard error: this surface never fails
  the check, so its fail-loud carve-out is explicit (contrast REQ-B1.8, whose
  fail-loud governs the deterministic manifest/exemption/knob inputs). The floor's
  default SHALL live in `config/defaults.yml`, overlay-tunable, with its
  `docs/options-reference.md` row (REQ-B1.4).
  *(Cites: D-13, D-5, kickoff §3 (2026-07-08), amendment (2026-07-09).)*
- **REQ-B1.8** The guard SHALL fail loud on the deterministic measurement
  input it cannot parse: a malformed or unrecognized doctrine-manifest entry, a
  malformed exemption/allowance entry, or a missing or non-numeric threshold
  knob SHALL be an error, never a silent skip, a silent zero, or a pass. An
  input that cannot be measured is not counted as under budget. A skill that
  declares **no** doctrine manifest is not an error (its start-load is scored
  body-only per REQ-A1.2); the missing-manifest error is reserved for a manifest
  that is present but malformed. The injected-context surface is carved out of
  this fail-loud rule: an injected-context hook whose static prose cannot be
  extracted is warn-only per REQ-B1.7, since that surface never fails the check.
  Threshold comparison SHALL be boundary-defined: a count **equal to** an error
  threshold is an error, and a count equal to a warn threshold is a warning
  (`≥`, not `>`).
  *(Cites: D-5, kickoff sign-off lens pass (2026-07-09), amendment (2026-07-09).)*
- **REQ-B1.9** The guard and audit run in CI over repository files that are
  PR-controllable (manifest entries, exemption/allowance text, rule-doc
  names, hook scripts). They SHALL treat that content as untrusted: no
  content is passed to a shell for evaluation, rule-doc resolution is confined
  to the resolution roots (no path traversal outside them), and hook scripts
  are read statically, never executed (REQ-A1.4).
  *(Cites: security-posture, kickoff sign-off lens pass (2026-07-09).)*

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
- **REQ-C1.6** The kept-eval convention SHALL require artifact hygiene and a
  standing CI-exclusion guard: recorded eval artifacts (results, cost) SHALL
  carry the per-fixture graded outcome, the fixture identifier, and cost — and
  nothing more — scrubbed of machine-local paths, usernames, and session
  identifiers, so no operational detail lands in a committed (public) artifact.
  The fixture identifier is retained deliberately: without it the D-7 paired
  before/after comparison (REQ-D1.3) cannot pair a baseline result to its
  post-diet counterpart on the identical fixture. And the "evals never run in CI"
  invariant
  (D-8) SHALL be enforced by a standing check over the CI workflow files —
  not by mere absence from the `check` aggregate — that fails if an eval task
  is wired into CI.
  *(Cites: D-8, security-posture, kickoff sign-off lens pass (2026-07-09).)*

## REQ-D — Diets & verification

- **REQ-D1.1** Each shortlisted offender SHALL be slimmed per its diet plan
  until it passes the guard (including a skill over the mandatory-at-start or
  reachable-closure budget, not only a file over its per-file floor); moved
  law SHALL be relocated verbatim in meaning (no contract change rides a
  diet).
  *(Cites: the invocation seed (Sources), D-5, kickoff §3 (2026-07-08).)*
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
  errors: the suppression list carries only permanent recorded exemptions
  (REQ-B1.3a), with no transitional `pending diet` allowances (REQ-B1.3b)
  remaining — per-file, mandatory-at-start, or reachable-closure. A lingering
  start-load or closure offender therefore surfaces as a lingering `pending diet`
  allowance, so the closeout check catches it.
  *(Cites: drafting-session decision (2026-07-08), kickoff sign-off lens pass (2026-07-09), amendment (2026-07-09).)*

## Changelog

- 2026-07-08 — Bundle drafted via `/spec-draft` (fold-detection ran against
  all nine non-terminal bundles; overlap with `specs/output-hygiene` judged
  a family boundary, spin-new triggers fired; zero observations-log entries
  consumed).
- 2026-07-08 — `/spec-kickoff` §3 (meaning-class): added REQ-A1.4 +
  REQ-B1.7 (injected-context measurement with a warn-only floor; new D-13);
  REQ-A1.1 excludes the `doctrine/README.md` index; REQ-A1.3 / REQ-D1.1
  clarified that the offender shortlist covers skills over the mandatory-at-start
  or reachable-closure budget, not only files over per-file floors; added Task 7.5
  (residual start-load diets) and a spec-format-coupling note on Task 7.
  Prompted by the corpus measurement (`/spec-draft` mandatory-at-start
  ≈10,460, over the 10,000 error threshold, with no diet task).
- 2026-07-09 — `/spec-kickoff` sign-off lens pass (meaning-class): the
  Discovery-Rigor fan-out found the Task-7.5 start-load remediation deadlocked
  (non-exemptible start-load + downstream-only fix) with an arithmetic error in
  the spec-format coupling. Redesign (Approach A): REQ-B1.3 now distinguishes a
  permanent exemption from a transitional `pending diet` allowance that may
  cover a start-load offender during its diet (seeded at Task 3, liquidated by
  Task 7.5, forbidden at Task 8); Task 7.5 scoped to start-load; coupling note
  corrected. Also: REQ-A1.4 fully specified (registered-hook discovery, static
  extraction rule, never-executed); REQ-B1.7 reconciled with REQ-A1.4 (row
  always shown, warn only above floor); added REQ-B1.8 (fail-loud on malformed
  input + boundary semantics), REQ-B1.9 (untrusted-input safety), REQ-C1.6
  (eval artifact hygiene + evals-never-in-CI standing guard). Terminology
  normalized.

- 2026-07-09 — Amendment (meaning-class), post-kickoff independent-model panel
  pass (gemini backend): five cross-file/interaction findings the same-session
  lens missed, all accepted. (F1) REQ-A1.2 / REQ-B1.8: a skill declaring no
  manifest scores start-load body-only (not an error); the hard missing-manifest
  error is reserved for a *malformed* manifest, and a manifest-completeness
  assertion (wired at Task 3) guards against silent under-report — resolving the
  Task-2-wires-guard-before-Task-3-adds-manifests deadlock. (F2) REQ-B1.3b /
  REQ-D1.4 / Task 8: the transitional `pending diet` allowance now also covers
  reachable-closure, the symmetric fix to the start-load deadlock. (F3) REQ-B1.8 /
  REQ-B1.7: an injected-context hook whose static prose cannot be extracted is
  warn-only, carved out of B1.8's fail-loud (which now governs only the
  deterministic manifest/exemption/knob inputs), consistent with D-13's never-fail
  surface. (F4) REQ-C1.6 / Task 4: recorded eval artifacts retain the per-fixture
  identifier so the D-7 paired comparison survives the scrub. (F5) REQ-B1.7:
  "exceeds the floor" → "meets or exceeds the floor" (align with B1.8's `≥`).
  Anchor recomputed; test-spec, tasks, and design updated in lockstep.

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
