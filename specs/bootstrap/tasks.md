# planwright Bootstrap — Tasks

**Status:** Active
**Last reviewed:** 2026-06-11
**Format-version:** 1

Tasks to build planwright v1. Foundational work (intelligence migration + meta-spec +
self-hosting CI) comes first; skills layer on the doctrine; the multi-contributor
work-repo end-to-end run is the final public-release gate condition (REQ-J1.5
condition (c)).

## Dependency graph

Layered view, derived from the `Dependencies:` lines below (which are
authoritative); `(←Tn)` lists each task's direct dependencies.

```
Level 0: T1 (scaffold) · T3 (intelligence) · T4 (meta-spec)
Level 1: T2 (self-hosting CI ←T1) · T5 (validator ←T4) · T7 (gate ←T3)
         T8 (spec-draft ←T3,T4) · T10 (drain ←T4) · T15 (eng doctrine ←T3)
Level 2: T6 (hooks ←T4,T5) · T9 (kickoff ←T4,T5) · T11 (self-review/polish ←T3,T7)
Level 3: T12 (execute-task ←T9,T11) · T14 (resume ←T9) · T17 (lifecycle ←T5,T8,T9)
Level 4: T13 (orchestrate ←T5,T6,T10,T12) · T16 (builder ←T7,T8,T10,T12,T15)
Level 5: T18 (work-repo E2E ←T13,T14,T16,T17)
Level 6: T19 (packaging ←T16,T17,T18)
```

Critical path (longest chain by estimated effort, 12.5d):
T3→T7→T11→T12→T13→T18→T19. T1, T3, T4 have no dependencies and are the natural
parallel start; under critical-path-first selection (REQ-F1.2), T3 (the
intelligence migration) dispatches first.

## Forward plan

### Task 12 — `/execute-task`

- **Deliverables:** The `/execute-task` skill: test-first discipline; adaptive CI retry;
  Research Rigor wiring (triggers fire pre-implementation; findings recorded in the risk
  register per REQ-D1.5); write-time security passes (REQ-D1.6); decision-domains drift
  triggers (REQ-G1.8); risk-register recording of research/perf/security tradeoffs;
  in-flight amendment per the axis (D-19); `/polish` convergence; draft PR referencing
  brief/tasks/REQs/tests and carrying the pending-sign-off checklist (REQ-E1.5);
  the execution freshness gate at pre-flight (anchor recompute against main's brief
  per the entry's recorded command; halt on mismatch or on an absent/unparseable/
  non-sanctioned entry, REQ-F1.9/F1.10/D-45); the marked expression-only
  self-re-anchor entry after in-flight expression fixes (REQ-F1.10); observation
  writing; the self-healing maintenance footer (REQ-B3.2).
- **Done when:** A task is implemented test-first (failing test precedes impl, ends green);
  transient CI retries and logic failures escalate; a research trigger produces a
  risk-register entry; a spec changed since the brief's last anchor (or an invalid
  anchor entry) halts with the REQ-F1.9 remedy named; an in-flight expression-only
  fix leaves a marked self-re-anchor entry; a draft PR is opened referencing the
  brief with the checklist.
- **Dependencies:** 9, 11
- **Citations:** D-11, D-19, D-39, D-42, D-45 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-E1.5, REQ-A3.3, REQ-D1.5, REQ-D1.6, REQ-B3.2, REQ-F1.9, REQ-F1.10, REQ-G1.8, REQ-J1.4, REQ-K1.7
- **Estimated effort:** 1.5 days

### Task 13 — `/orchestrate`

- **Deliverables:** The `/orchestrate` stateless step machine: critical-path-first ready-unit
  selection; per-spec advisory lock (state-move-only, 15-min stale-break); one-unit-per-step;
  cohesion-first bundling; the control-tower dispatch layer (D-38): subagent backend
  (default), tmux backend (opt-in, capture-pane detection), print backend, in-session,
  unattended mode (headless: no confirms, prompts → Awaiting input), the shipped
  worker-settings profile, `--watch` (event-driven under subagents, polling under tmux),
  the reconcile sweep, `max_parallel_units` cap; worktree create/reuse via native
  `claude --worktree` mechanics (D-37); auto-commit of `tasks.md` state moves (D-41);
  halt-to-Awaiting-input; draft-PR-only; the `--bookkeeping` drain pass (gate evaluation +
  out-of-session merge reconciliation + observation-staleness surfacing per REQ-H1.4);
  refusal on non-Active specs with no auto-chain; the execution freshness gate inside
  the D-10 lock window immediately before the `tasks.md` update (anchor recompute per
  the entry's recorded command against the primary checkout's main view; halt to
  Awaiting input on mismatch or on an absent/unparseable/non-sanctioned entry,
  REQ-F1.9/F1.10/D-45); the self-healing maintenance footer
  (REQ-B3.2).
- **Done when:** One step advances exactly one ready unit; concurrent invocations don't
  collide; a non-Active spec halts with a kickoff prompt; each backend dispatches a worker
  that completes a unit; the reconcile sweep recovers from a killed tower and orphans an
  In-progress task per the tightened REQ-F1.1 predicate (PR-state reconciled first;
  grace threshold; observable backend; positive evidence of death; print-backend
  exempt) to Awaiting input with an orphan note; a missing validator halts a dispatch
  step with a clear message (REQ-K1.7); unattended mode records prompts as
  Awaiting-input entries; a spec changed since the brief's last anchor (or an
  invalid anchor entry) halts the dispatch step with the REQ-F1.9 remedy named;
  an orchestrate state move does not change the anchor while an edited Done-when
  does; `--bookkeeping` re-surfaces satisfied gates
  without auto-dropping.
- **Dependencies:** 5, 6, 10, 12
- **Citations:** D-7, D-8, D-9, D-10, D-31, D-36, D-37, D-38, D-41, D-45 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4, REQ-F1.5, REQ-F1.6, REQ-F1.7, REQ-F1.8, REQ-F1.9, REQ-F1.10, REQ-H1.4, REQ-J1.1, REQ-J1.2, REQ-J1.3, REQ-J1.4, REQ-K1.7, REQ-B3.2
- **Estimated effort:** 3 days

### Task 14 — `/resume`

- **Deliverables:** The `/resume` read-only context loader: kickoff brief + `tasks.md` + git
  log + PR state + optional handover brief; surfaces uncommitted changes and asks before
  proceeding; no auto-stash/commit/clean; the self-healing maintenance footer (REQ-B3.2).
- **Done when:** A fresh session in an in-flight worktree gets the loaded context and a
  `git status` surfacing with a proceed prompt.
- **Dependencies:** 9
- **Citations:** D-30, D-42 · REQ-F2.1, REQ-B3.2
- **Estimated effort:** half day

### Task 16 — Builder skill + core catalog + lifecycle hooks

- **Deliverables:** The builder skill: stack detection; the extensible core guard catalog
  (formatter, linter, type-checker, test runner, secret/security scan, prose/doc linters
  per the widened tool-grounding amendment to D-15/D-39 (kickoff brief, Section 3), CI
  gate, commit hooks) with breadth dimensions
  (docs, i18n, a11y, architecture) as growable entries; escalation of stake-bearing
  decisions into the deferral mechanism (consuming the decision-domains catalog, D-39);
  hooks into `/spec-draft` (design phase) and `/execute-task` (applies guards); the
  self-healing maintenance footer (REQ-B3.2).
- **Done when:** The builder detects a project's stack and recommends/applies the core guards;
  an auth-class decision is escalated (not auto-defaulted) and routed into a gate; **the
  builder, run against planwright itself, reproduces the guard set established in Task 2**
  (dogfood loop).
- **Dependencies:** 7, 8, 10, 12, 15
- **Citations:** D-15, D-16, D-32 · REQ-G1.2, REQ-G1.4, REQ-G1.5, REQ-G1.7
- **Estimated effort:** 1.5 days

### Task 17 — Spec lifecycle & evolution mechanics

- **Deliverables:** The amendment ritual (fix-in-place + mandatory changelog vs. supersede +
  scoped re-sign-off) wired into `/execute-task` and `/spec-kickoff`; the fold-vs-new rule and
  extend mechanics wired into `/spec-draft`; supersede / changelog / never-reused-ID
  enforcement added to the validator.
- **Done when:** An expression-only edit needs only a changelog; a decision-contradicting edit
  triggers supersede + scoped re-sign-off; the validator rejects a reused ID and accepts a
  supersede; `/spec-draft` extend mode appends without renumbering.
- **Dependencies:** 5, 8, 9
- **Citations:** D-19, D-20, D-21 · REQ-A3.2, REQ-A3.3, REQ-A3.4
- **Estimated effort:** 1 day

### Task 18 — Multi-contributor work-repo end-to-end validation run

- **Deliverables:** A full planwright pipeline run on a real multi-contributor work repo
  (a qualifying private work repo exists): draft → kickoff → orchestrate → execute →
  polish → draft PR,
  confirming the act-then-review flow (pending-sign-off checklist in the PR body, declined
  log, hard pauses firing where expected); a findings document covering the gate behavior,
  kickoff-brief effectiveness, dispatch-backend behavior, and the **manual-verification
  sweep**: a checklist of every test-spec entry whose tag includes [manual] or
  [Gherkin] (mixed tags count) — exercised, or the gap named.
- **Done when:** At least one work-project task is executed via the pipeline; the findings
  doc covers the gate behavior and contains the completed manual-sweep checklist; the
  public-release gate condition (c) is met. Validating across a second distinct work repo
  is a deferred stretch (see Deferred).
- **Dependencies:** 13, 14, 16, 17
- **Citations:** D-5, D-27, D-38 · REQ-C1.3, REQ-J1.5
- **Estimated effort:** 2 days

### Task 19 — Packaging finalization & onboarding docs

- **Deliverables:** Finalized plugin manifest + `~/.claude/` writer; adopter onboarding docs
  (autopilot model, how to supply project-specific tooling/rigor without editing core docs,
  the GitHub/`gh` requirement and graceful-degradation behavior); contribution model;
  public-release readiness checklist enforcing the three gate conditions plus every
  release-blocking gated Deferred entry (currently the `reference/` history purge,
  human-reserved per REQ-J1.4: the checklist verifies it happened, it does not perform
  it). *(Amended at panel review 2026-06-11: checklist scope widened to cover
  release-blocking Deferred entries; brief Risk Register row 8 already claimed this
  enforcement.)*
- **Done when:** A clean machine can install planwright both ways and resolve rule docs; the
  onboarding docs let a non-author operate the pilot-in-command model; the release checklist
  enumerates and checks the three gate conditions and every release-blocking gated
  Deferred entry (the `reference/` history purge).
- **Dependencies:** 16, 17, 18
- **Citations:** D-24, D-27, D-29, D-35 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-D2.2, REQ-K1.6, REQ-J1.4, REQ-J1.5
- **Estimated effort:** 1 day

## Completed

### Task 3 — Migrate framework intelligence into doctrine docs

- **Deliverables:** Standalone planwright doctrine docs reworded from `CLAUDE.md` into
  framework documentation: Finding Categorization (four buckets + predicates, act-then-review
  dispositions incl. declined-with-rationale and the resolution ladder per D-5), Validation
  Rigor (incl. the altitude check), Discovery Rigor, Refactor Instinct, **Research Rigor**
  (triggers, source hierarchy, recency discipline, antipattern check, risk-register
  recording per REQ-D1.5), **Security posture** (write-time triggers, artifact
  data-hygiene, framework-script security per REQ-D1.6), the proportionality principle
  (REQ-D1.7), and the composability-by-default principle. Personal content (fish/mise/tmux,
  git conventions, the author's repos) is NOT migrated.
- **Done when:** Each doctrine doc exists as framework prose (no first-person personal
  instructions); the four buckets, the three-pass validation, the lens checklist, the
  refactor bars, the research ritual, and the security posture are all present; skills can
  reference them via the resolution path (Task 1).
- **Dependencies:** none
- **Citations:** D-4, D-5 · REQ-C1.1, REQ-C1.2, REQ-C1.6, REQ-C1.7, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5, REQ-D1.6, REQ-D1.7, REQ-D2.1
- **Estimated effort:** 2.5 days
- **Status:** Completed · PR #2 merged 2026-06-11
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-3` · dispatched 2026-06-11T20:42Z ·
  branch `planwright/bootstrap/task-3` · worktree `.claude/worktrees/task-3`

### Task 1 — Repo scaffold & packaging skeleton

- **Deliverables:** Plugin manifest skeleton; `~/.claude/` writer stub; the stable
  plugin-relative rule-doc resolution path convention; config-model skeleton (tracked
  default + gitignored local override per D-33, including the commit/dispatch toggles
  per D-41/D-38); the canonical options-reference skeleton (D-43); MIT `LICENSE`;
  `README` introducing the autopilot / pilot-in-command model; `.gitignore` entries
  for the local config + worktrees.
- **Done when:** A fresh checkout exposes the plugin manifest and writer entry points; the
  rule-doc resolution path resolves from both delivery modes; `LICENSE` is MIT; the README
  states the human-reserved controls; every option in the default config has an
  options-reference entry.
- **Dependencies:** none
- **Citations:** D-24, D-27, D-28, D-29, D-33, D-41, D-43 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.5, REQ-K1.1, REQ-K1.8
- **Estimated effort:** half day
- **Status:** Completed · PR #3 merged 2026-06-11
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-1` · dispatched 2026-06-11T20:57Z ·
  branch `planwright/bootstrap/task-1` · worktree `.claude/worktrees/task-1`

### Task 2 — Self-hosting: quality guards & CI

- **Deliverables:** planwright's own quality guards and CI — `markdownlint` (doctrine/docs),
  `shellcheck` + `shfmt` (scripts/hooks), JSON/YAML lint (manifest/config), a doctrine
  cross-reference link-check, `gitleaks` secret scan, conventional-commit lint, a shell test
  runner for validator/parser/lock unit tests, and a GitHub Actions CI pipeline running all of
  it on every PR; the planwright spec validator runs against planwright's own `specs/` in CI;
  the options-reference drift check (fail on an undocumented config option, D-43).
- **Done when:** CI is green on a trivial PR and red on a seeded violation of each guard
  (including a seeded undocumented config option); all subsequent tasks merge only under
  green CI.
- **Dependencies:** 1
- **Citations:** D-32, D-34, D-43 · REQ-G1.7, REQ-K1.5, REQ-K1.8
- **Estimated effort:** 1 day
- **Status:** Completed · PR #7 merged 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-2` · dispatched 2026-06-11T23:55Z ·
  branch `planwright/bootstrap/task-2` · worktree `.claude/worktrees/task-2`

### Task 7 — Finding categorization & act-then-review gate wiring

- **Deliverables:** The autonomy-gate wiring that routes findings through the four buckets
  with act-then-review dispositions: on-branch application of Needs-sign-off items,
  pending-sign-off checklist generation for the draft PR body, the declined-with-rationale
  audit log, the resolution ladder (brief → research → convention) before the judgment
  bucket, and the hard-pause triggers (disqualifier zones + irreducible forks).
- **Done when:** A Needs-sign-off finding is applied on-branch and appears in the checklist;
  a declined finding carries its rationale in the audit table; a fork resolvable from the
  brief never reaches the human; a disqualifier-zone finding pauses; all four tables emit
  including empties.
- **Dependencies:** 3
- **Citations:** D-4, D-5, D-6 · REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7
- **Estimated effort:** 1 day
- **Status:** Completed · PR #5 merged 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-7` · dispatched 2026-06-11T22:14Z ·
  branch `planwright/bootstrap/task-7` · worktree `.claude/worktrees/task-7`

### Task 4 — Four-file format meta-spec

- **Deliverables:** The canonical four-file format meta-spec: required fields per file,
  REQ-ID / D-ID conventions, citation syntax and lightweight citation kinds (e.g.
  "drafting-session decision"), the per-task required fields, the five-status lifecycle
  with the reopen cycle (D-40), the Changelog section location, the `Format-version:`
  declaration, the stable-ID / supersede / changelog rules, the kickoff brief structure,
  a glossary of framework vocabulary covering at minimum: the three senses of gate;
  unit; drain; accumulator; adopter; brief; bucket; tower (the dispatching session);
  the observations log (canonical name for `specs/_observations/opportunities.md`);
  dispatch step; content anchor; execution-valid (anchor); meaning-class vs
  expression-only (the REQ-A3.3 axis).
  Plus the format conventions: the spec-identifier charset (REQ-A1.8), the
  path-placeholder style (angle brackets: `<spec>`, `<id>`), the superseding-REQ
  placement rule (a superseding REQ sits adjacent to the REQ it supersedes, e.g.
  B2.4 beside B2.1), the amendment-annotation format (`*(Amended at <event>
  <date>: …)*`), the amendment-ritual scope rule (pre-merge corrections on the
  spec's own PR amend in place with a changelog entry + recorded re-sign-off;
  the REQ-A3.3 supersede ritual governs post-merge changes), the
  underscore-prefix marker for non-spec accumulator directories (REQ-A1.8),
  the canonical tasks.md definition-content extraction for the content anchor
  (REQ-F1.9), the sign-off record format (Class / self-describing Anchor /
  Lens-pass fields and the sanctioned command forms, REQ-F1.10),
  and the validator-enforceable invariants. Bring this bundle into
  format conformance (backfill per-REQ citations).
- **Done when:** The meta-spec fully specifies the format this very bundle conforms to
  (including backfilled citations); a reader could author a compliant bundle from it
  alone; the kickoff brief structure and glossary are specified.
- **Dependencies:** none
- **Citations:** D-1, D-20, D-25, D-40 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-B2.2
- **Estimated effort:** 1.5 days
- **Status:** Completed · PR #4 merged 2026-06-12
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-4` · dispatched 2026-06-11T20:55Z ·
  branch `planwright/bootstrap/task-4` · worktree `.claude/worktrees/task-4`

### Task 15 — Engineering decision-process doctrine doc

- **Deliverables:** The engineering doctrine doc encoding the decision process: prefer
  framework/language/stack idioms while keeping domain logic composable; defer to tooling and
  ecosystem standards; research mature-project solutions when no clean best-practice fits;
  the stake-awareness rule (escalate load-bearing "mechanical" decisions); the
  dependency-adoption checklist (REQ-G1.1); priority-balancing nuance. Plus the
  decision-domains catalog doctrine (D-39): the entry format (trigger + considerations +
  disposition) and the ~10 seed domain entries (REQ-G1.8).
- **Done when:** The doc specifies the decision process, the ecosystem-research move, and the
  escalation rule with the auth-class example; the catalog format and seed entries exist;
  it is referenceable via the resolution path.
- **Dependencies:** 3
- **Citations:** D-15, D-16, D-39 · REQ-G1.1, REQ-G1.3, REQ-G1.6, REQ-G1.8
- **Estimated effort:** 1.5 days
- **Status:** Completed · PR #6 merged 2026-06-12
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-15` · dispatched 2026-06-11T22:16Z ·
  branch `planwright/bootstrap/task-15` · worktree `.claude/worktrees/task-15`

### Task 11 — `/self-review` + `/polish`

- **Deliverables:** `/self-review` (Discovery + Validation rigor against the feature branch,
  four-table output including empties); `/polish` (autonomous act-then-review loop:
  applies Auto-applicable, Agent-resolvable, and Needs-sign-off items per REQ-C1.3,
  records declined-with-rationale dispositions, walks the resolution ladder, local-only,
  until only irreducible judgment forks remain). Both append observations to the
  observations log and carry the self-healing maintenance footer (REQ-B3.2).
- **Done when:** `/polish` drains all action dispositions, emits all four tables plus the
  declined log and pending-sign-off checklist; the observations log gains entries; nested
  invocation fires hooks once (in-session).
- **Dependencies:** 3, 7
- **Citations:** D-12, D-13, D-42 · REQ-E2.1, REQ-E2.2, REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-B3.2
- **Estimated effort:** 1.5 days
- **Status:** Completed · PR #8 merged 2026-06-12
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-11` · dispatched 2026-06-12T19:35Z ·
  branch `planwright/bootstrap/task-11` · worktree `.claude/worktrees/task-11`

### Task 5 — Status-aware validator

- **Deliverables:** A portable-shell validator enforcing four-file presence, per-task
  structure (stable ID, Done when, Dependencies, Citations), REQ↔test-spec coverage, and the
  stable-ID/never-reused rule; the spec-identifier charset check (REQ-A1.8,
  skipping underscore-prefixed accumulator directories);
  status-aware across all five statuses (warnings on Draft,
  errors on Active; Retired/Superseded treated as terminal — `Superseded-by:` required on
  Superseded; reopen-cycle transitions accepted per D-40); keyed off the declared
  format-version. Unit tests for each check.
- **Done when:** The validator passes on a valid bundle, warns on a Draft gap, errors on the
  same gap when Active, rejects a reused ID, rejects Superseded without `Superseded-by:`;
  it runs in planwright's own CI (Task 2).
- **Dependencies:** 4
- **Citations:** D-25, D-34 · REQ-A1.8, REQ-A2.1, REQ-A2.2, REQ-A3.2
- **Estimated effort:** 1 day
- **Status:** Completed · PR #9 merged 2026-06-12
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-5` · dispatched 2026-06-12T20:30Z ·
  branch `planwright/bootstrap/task-5` · worktree `.claude/worktrees/task-5`

## In progress

### Task 10 — Accumulator taxonomy & `GATE(when:)` convention + `/drain`

- **Deliverables:** The accumulator-taxonomy doctrine doc (three classes + drain ritual each);
  the `GATE(when: …)` convention and a portable-shell gate parser/evaluator (condition gates,
  date-gates-surface-only, confidence levels; closed declarative grammar parsed by pattern
  match, never `eval`, per REQ-H1.3 — the doctrine doc is the normative home for the
  grammar productions: atom forms, the `and`-of-atoms combinator, and the surface-only
  free-text gate class); the `/drain` skill front-end over the evaluator; the
  self-healing maintenance footer (REQ-B3.2).
- **Done when:** A satisfied condition gate re-surfaces its item; a date gate only surfaces;
  nothing is auto-resolved or auto-dropped; `/drain` and the bookkeeping pass call the same
  evaluator; a hostile or malformed gate entry is surfaced as an error, never evaluated or
  silently skipped.
- **Dependencies:** 4
- **Citations:** D-17, D-18, D-31, D-42 · REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4, REQ-H1.5, REQ-B3.2
- **Estimated effort:** 1 day
- **Status:** draft-pr-ready · PR #10 (draft)
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-10` · dispatched 2026-06-12T20:30Z ·
  branch `planwright/bootstrap/task-10` · worktree `.claude/worktrees/task-10`

### Task 8 — `/spec-draft`

- **Deliverables:** The `/spec-draft` skill: interactive four-file elicitation at Status Draft;
  auto-commit of the completed bundle (`commit_on_draft` opt-out, D-41); fold-detection
  (always-scan, surface, human decides) with an extend mode; `_observations` seed mining +
  archive-on-consume; seed-source citation; interaction-style rules; the builder/catalog
  hook point (the builder plugs in via Task 16 — no dependency edge by design); spec
  worktree + branch creation (`planwright/<spec>/spec`) with graceful handling of every
  starting state per D-44 (reuse, locate-and-print, create, degrade on no-repo); the
  self-healing maintenance footer (REQ-B3.2).
- **Done when:** A run produces and commits a Draft bundle on the spec branch without
  pushing/flipping Active; launching from main, from the spec worktree, and from an
  unrelated worktree each resolves gracefully; fold-detection surfaces an extend
  recommendation on a differently-named overlap; consumed opportunities are archived;
  the maintenance footer writes drift observations.
- **Dependencies:** 3, 4
- **Citations:** D-21, D-22, D-23, D-41, D-42, D-44 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B3.1, REQ-B3.2, REQ-H1.6
- **Estimated effort:** 1.5 days
- **Status:** draft-pr-ready · PR #11 (draft)
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-8` · dispatched 2026-06-12T21:55Z ·
  branch `planwright/bootstrap/task-8` · worktree `.claude/worktrees/task-8`

### Task 6 — Hooks & operational integration

- **Deliverables:** The `tasks-pr-sync` PostToolUse hook (moves task blocks between `tasks.md`
  sections on `gh pr create` / `gh pr merge`, parsing the branch convention); the
  `tool-discovery` SessionStart hook (detects linters/formatters/type-checkers, feeds
  Discovery Rigor and the builder); the branch-naming and worktree-placement conventions
  (including the reserved `planwright/<spec>/spec` namespace the sync hook no-ops on,
  D-44); config-model wiring.
- **Done when:** Creating/merging a PR on a convention-named branch moves the matching task
  block to the right section; a session start emits the discovered-tools summary; the hooks
  no-op cleanly on non-matching input, including hostile branch names (segments failing
  the REQ-A1.8 charset, `..`, path separators).
- **Dependencies:** 4, 5
- **Citations:** D-33, D-36, D-37, D-44 · REQ-K1.2, REQ-K1.3, REQ-K1.4
- **Estimated effort:** 1 day
- **Status:** implementing
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-6` · dispatched 2026-06-12T23:35Z ·
  branch `planwright/bootstrap/task-6` · worktree `.claude/worktrees/task-6`

### Task 9 — `/spec-kickoff`

- **Deliverables:** The `/spec-kickoff` skill: section-by-section walkthrough to mutual
  understanding; incremental kickoff-brief authoring against the specified brief structure
  (risk register, decisions, task graph, verification); the decision-domains gap check
  (flags catalogued domains the spec touches but does not decide, into the risk register —
  degrades gracefully until Task 15 lands; no dependency edge by design); inconsistency
  halt with the edit-or-override resolution; Draft→Active flip on sign-off; auto-commit of
  brief + flip (`commit_on_kickoff` opt-out, D-41); push of the spec branch + draft PR
  (REQ-B2.4, D-44), degrading gracefully on no remote / `gh` failure (Awaiting-input note,
  local work intact); spec-worktree reuse/recreate per D-44 (including recreating a pruned
  worktree from the spec branch); `Last reviewed:` update; the sign-off content anchor
  written on every sign-off, amendment, and re-walkthrough per the REQ-F1.10 record
  format, anchor line written last (REQ-F1.9, D-45); the Discovery-Rigor lens review
  pass as part of sign-off (fan-out per Discovery Rigor for non-trivial deltas; full
  bundle at first activation, delta-scoped at re-walkthroughs and amendments, skipped
  for expression-only changes per REQ-A3.3), findings dispositioned and the pass
  recorded in the brief; the self-healing maintenance footer (REQ-B3.2).
- **Done when:** A walkthrough produces a signed brief, flips the spec Active, commits,
  pushes, and opens a draft PR (or records the degradation note when no remote exists);
  every sign-off carries a recomputable content anchor in the REQ-F1.10 format; a
  meaning-class sign-off without a dispositioned lens pass refuses to record an
  execution-valid anchor; launching from main, the spec
  worktree, or an unrelated worktree each resolves
  gracefully; a seeded contradiction halts without a brief; a killed session leaves a
  resumable partial brief.
- **Dependencies:** 4, 5
- **Citations:** D-3, D-19, D-39, D-41, D-42, D-44, D-45 · REQ-B2.4, REQ-B2.2, REQ-B2.3, REQ-B3.2, REQ-A3.1, REQ-F1.9, REQ-F1.10, REQ-G1.4, REQ-K1.7
- **Estimated effort:** 1 day
- **Status:** draft-pr-ready · PR #12 (draft)
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux · window=`pw-bootstrap-task-9` · dispatched 2026-06-12T23:35Z ·
  branch `planwright/bootstrap/task-9` · worktree `.claude/worktrees/task-9`

## Awaiting input

(none yet)

## Deferred

- **Second multi-contributor validation repo.** Validating the pipeline across a second distinct
  work repo (beyond Task 18's first) is the user's stated ideal. **Gate:** Task 18 completed and
  a second eligible work repo is available. Citations: REQ-J1.5.
- **Purge `reference/` from main's history.** `reference/` is tracked for now so worktrees can
  access the migration source material, but it is transient and may contain personal/work data
  that must not persist in history. A deliberate human history rewrite (e.g. `git filter-repo`)
  removes it. Confidence: high. Scope widened at self-review 2026-06-10: the purge also
  covers spec-file blobs in pre-neutralization commits (work-repo identifiers removed from
  file content on 2026-06-10 survive in this branch's earlier commits). **Gate:** all
  `reference/`-citing tasks Completed (notably Task 3)
  AND before any public release. Citations: D-27, REQ-J1.5, REQ-J1.4 (human-reserved action, not
  an autopilot one).

## Out of scope

- **Cross-session awareness layer** (inbox/heartbeat/tmux dashboard, pair-flow REQ-F). Fast-follow
  spec; out of v1 per D-14.
- **`/peer-review`, `/code-review`, `/panel-*`, `/copilot-*`** review workflows. Fast-follows;
  v1 ships only the gate-wired review core per D-12.
- **Non-GitHub git hosts** (GitLab, Bitbucket) for the PR flow. Fast-follow per D-35.
- **The work fork and migrating the author's own dotfiles** onto planwright. Out per the seed.
