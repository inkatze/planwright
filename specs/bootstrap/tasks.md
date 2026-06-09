# planwright Bootstrap — Tasks

**Status:** Draft
**Last reviewed:** 2026-06-09
**Format-version:** 1

Tasks to build planwright v1. Foundational work (intelligence migration + meta-spec +
self-hosting CI) comes first; skills layer on the doctrine; the multi-reviewer
end-to-end run is the public-release gate.

## Dependency graph

```
T1 ─→ T2 (self-hosting CI) ──────────────────────────────────────────┐
T3 (intelligence) ─┬─→ T7 (gate) ─→ T11 (self-review/polish) ─→ T12 ─┐│
                   ├─→ T8 (spec-draft) ──────────────┐               ││
                   └─→ T15 (eng doctrine) ─→ T16 (builder) ──┐        ││
T4 (meta-spec) ─→ T5 (validator) ─┬─→ T6 (hooks) ─→ T13 (orchestrate)─┤│
                  └─→ T9 (kickoff) ─┬─→ T12 (execute-task) ───────────┤│
T4 ─→ T10 (drain) ─────────────────┘                                  ││
T9 ─→ T14 (resume) ───────────────────────────────────────────────────┤
T5,T8,T9 ─→ T17 (lifecycle mechanics) ────────────────────────────────┤
T13,T14,T16,T17 ─→ T18 (multi-reviewer E2E gate) ─→ T19 (packaging) ◄──┘
```

Critical path: T4→T5→T6→T13→T18→T19 (with T3→T15→T16→T18 alongside). T1, T3, T4 have
no dependencies and are the natural parallel start.

## Forward plan

### Task 1 — Repo scaffold & packaging skeleton

- **Deliverables:** Plugin manifest skeleton; `~/.claude/` writer stub; the stable
  plugin-relative rule-doc resolution path convention; config-model skeleton (tracked
  default + gitignored local override per D-33); MIT `LICENSE`; `README` introducing the
  autopilot / pilot-in-command model; `.gitignore` entries for the local config + worktrees.
- **Done when:** A fresh checkout exposes the plugin manifest and writer entry points; the
  rule-doc resolution path resolves from both delivery modes; `LICENSE` is MIT; the README
  states the human-reserved controls.
- **Dependencies:** none
- **Citations:** D-24, D-27, D-28, D-29, D-33 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.5, REQ-K1.1
- **Estimated effort:** half day

### Task 2 — Self-hosting: quality guards & CI

- **Deliverables:** planwright's own quality guards and CI — `markdownlint` (doctrine/docs),
  `shellcheck` + `shfmt` (scripts/hooks), JSON/YAML lint (manifest/config), a doctrine
  cross-reference link-check, `gitleaks` secret scan, conventional-commit lint, a shell test
  runner for validator/parser/lock unit tests, and a GitHub Actions CI pipeline running all of
  it on every PR; the planwright spec validator runs against planwright's own `specs/` in CI.
- **Done when:** CI is green on a trivial PR and red on a seeded violation of each guard; all
  subsequent tasks merge only under green CI.
- **Dependencies:** 1
- **Citations:** D-32, D-34 · REQ-G1.7, REQ-K1.5
- **Estimated effort:** 1 day

### Task 3 — Migrate framework intelligence into doctrine docs

- **Deliverables:** Standalone planwright doctrine docs reworded from `CLAUDE.md` into
  framework documentation: Finding Categorization (four buckets + predicates), Validation
  Rigor, Discovery Rigor, Refactor Instinct, and the composability-by-default principle.
  Personal content (fish/mise/tmux, git conventions, the author's repos) is NOT migrated.
- **Done when:** Each doctrine doc exists as framework prose (no first-person personal
  instructions); the four buckets, the three-pass validation, the lens checklist, and the
  refactor bars are all present; skills can reference them via the resolution path (Task 1).
- **Dependencies:** none
- **Citations:** D-4 · REQ-C1.1, REQ-C1.2, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D2.1
- **Estimated effort:** 2 days

### Task 4 — Four-file format meta-spec

- **Deliverables:** The canonical four-file format meta-spec: required fields per file,
  REQ-ID / D-ID conventions, the per-task required fields, the status lifecycle, the
  `Format-version:` declaration, the stable-ID / supersede / changelog rules, the kickoff
  brief structure, and the validator-enforceable invariants.
- **Done when:** The meta-spec fully specifies the format this very bundle conforms to; a
  reader could author a compliant bundle from it alone; the kickoff brief structure is
  specified.
- **Dependencies:** none
- **Citations:** D-1, D-20, D-25 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-B2.2
- **Estimated effort:** 1 day

### Task 5 — Status-aware validator

- **Deliverables:** A portable-shell validator enforcing four-file presence, per-task
  structure (stable ID, Done when, Dependencies, Citations), REQ↔test-spec coverage, and the
  stable-ID/never-reused rule; status-aware (warnings on Draft, errors on Active); keyed off
  the declared format-version. Unit tests for each check.
- **Done when:** The validator passes on a valid bundle, warns on a Draft gap, errors on the
  same gap when Active, and rejects a reused ID; it runs in planwright's own CI (Task 2).
- **Dependencies:** 4
- **Citations:** D-25, D-34 · REQ-A2.1, REQ-A2.2, REQ-A3.2
- **Estimated effort:** 1 day

### Task 6 — Hooks & operational integration

- **Deliverables:** The `tasks-pr-sync` PostToolUse hook (moves task blocks between `tasks.md`
  sections on `gh pr create` / `gh pr merge`, parsing the branch convention); the
  `tool-discovery` SessionStart hook (detects linters/formatters/type-checkers, feeds
  Discovery Rigor and the builder); the branch-naming and worktree-placement conventions;
  config-model wiring (read/confirm/write repo-class).
- **Done when:** Creating/merging a PR on a convention-named branch moves the matching task
  block to the right section; a session start emits the discovered-tools summary; the hooks
  no-op cleanly on non-matching input.
- **Dependencies:** 4, 5
- **Citations:** D-33, D-36, D-37 · REQ-K1.2, REQ-K1.3, REQ-K1.4
- **Estimated effort:** 1 day

### Task 7 — Finding categorization & autonomy gate wiring + repo-class detection

- **Deliverables:** The autonomy-gate wiring that routes findings through the four buckets and
  applies the solo/multi-reviewer split; repo-class detection (infer from PR history, surface
  for confirmation, multi-reviewer on ambiguity, write only on confirm) reading/writing the
  config model.
- **Done when:** Given a solo repo, Agent-resolvable auto-applies; given a multi-reviewer repo,
  it surfaces with evidence; ambiguous signals default to multi-reviewer; no repo-class is
  written without confirmation.
- **Dependencies:** 3
- **Citations:** D-4, D-5, D-6 · REQ-C1.3, REQ-C1.4, REQ-C1.5
- **Estimated effort:** 1 day

### Task 8 — `/spec-draft`

- **Deliverables:** The `/spec-draft` skill: interactive four-file elicitation at Status Draft;
  fold-detection (always-scan, surface, human decides) with an extend mode; `_observations`
  seed mining + archive-on-consume; seed-source citation; interaction-style rules.
- **Done when:** A run produces a Draft bundle without committing/pushing/flipping Active;
  fold-detection surfaces an extend recommendation on a differently-named overlap; consumed
  opportunities are archived.
- **Dependencies:** 3, 4
- **Citations:** D-21, D-22, D-23 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B3.1, REQ-H1.6
- **Estimated effort:** 1.5 days

### Task 9 — `/spec-kickoff`

- **Deliverables:** The `/spec-kickoff` skill: section-by-section walkthrough to mutual
  understanding; incremental kickoff-brief authoring against the specified brief structure
  (risk register, decisions, task graph, verification); inconsistency halt with the
  edit-or-override resolution; Draft→Active flip on sign-off; `Last reviewed:` update.
- **Done when:** A walkthrough produces a signed brief and flips the spec Active; a seeded
  contradiction halts without a brief; a killed session leaves a resumable partial brief.
- **Dependencies:** 4, 5
- **Citations:** D-3, D-19 · REQ-B2.1, REQ-B2.2, REQ-B2.3, REQ-A3.1
- **Estimated effort:** 1 day

### Task 10 — Accumulator taxonomy & `GATE(when:)` convention + `/drain`

- **Deliverables:** The accumulator-taxonomy doctrine doc (three classes + drain ritual each);
  the `GATE(when: …)` convention and a portable-shell gate parser/evaluator (condition gates,
  date-gates-surface-only, confidence levels); the `/drain` skill front-end over the evaluator.
- **Done when:** A satisfied condition gate re-surfaces its item; a date gate only surfaces;
  nothing is auto-resolved or auto-dropped; `/drain` and the bookkeeping pass call the same
  evaluator.
- **Dependencies:** 4
- **Citations:** D-17, D-18, D-31 · REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4, REQ-H1.5
- **Estimated effort:** 1 day

### Task 11 — `/self-review` + `/polish`

- **Deliverables:** `/self-review` (Discovery + Validation rigor against the feature branch,
  four-table output including empties); `/polish` (autonomous loop applying Auto-applicable
  items, plus Agent-resolvable in solo repos with an active brief, local-only, until both
  action buckets are empty). Both append observations to the opportunities log.
- **Done when:** `/polish` drains both action buckets and emits all four tables; the
  opportunities log gains entries; nested invocation fires hooks once (in-session).
- **Dependencies:** 3, 7
- **Citations:** D-12, D-13 · REQ-E2.1, REQ-E2.2, REQ-C1.5
- **Estimated effort:** 1.5 days

### Task 12 — `/execute-task`

- **Deliverables:** The `/execute-task` skill: test-first discipline; adaptive CI retry; risk-
  register recording of research/perf/security tradeoffs; in-flight amendment per the axis
  (D-19); `/polish` convergence; draft PR referencing brief/tasks/REQs/tests; observation
  writing.
- **Done when:** A task is implemented test-first (failing test precedes impl, ends green);
  transient CI retries and logic failures escalate; a draft PR is opened referencing the brief.
- **Dependencies:** 9, 11
- **Citations:** D-11, D-19 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-E1.5, REQ-A3.3
- **Estimated effort:** 1.5 days

### Task 13 — `/orchestrate`

- **Deliverables:** The `/orchestrate` stateless step machine: ready-unit selection; per-spec
  advisory lock (state-move-only, 15-min stale-break); one-unit-per-invocation; cohesion-first
  bundling; worktree create/reuse compatible with `claude --worktree`; halt-to-Awaiting-input;
  draft-PR-only; the `--bookkeeping` drain pass (gate evaluation + out-of-session merge
  reconciliation); refusal on non-Active specs with no auto-chain.
- **Done when:** One invocation advances exactly one ready unit and exits; concurrent
  invocations don't collide; a non-Active spec halts with a kickoff prompt; `--bookkeeping`
  re-surfaces satisfied gates without auto-dropping.
- **Dependencies:** 5, 6, 10, 12
- **Citations:** D-7, D-8, D-9, D-10, D-31, D-36, D-37 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4, REQ-F1.5, REQ-F1.6, REQ-F1.7, REQ-J1.2, REQ-J1.3
- **Estimated effort:** 2 days

### Task 14 — `/resume`

- **Deliverables:** The `/resume` read-only context loader: kickoff brief + `tasks.md` + git
  log + PR state + optional handover brief; surfaces uncommitted changes and asks before
  proceeding; no auto-stash/commit/clean.
- **Done when:** A fresh session in an in-flight worktree gets the loaded context and a
  `git status` surfacing with a proceed prompt.
- **Dependencies:** 9
- **Citations:** D-30 · REQ-F2.1
- **Estimated effort:** half day

### Task 15 — Engineering decision-process doctrine doc

- **Deliverables:** The engineering doctrine doc encoding the decision process: prefer
  framework/language/stack idioms while keeping domain logic composable; defer to tooling and
  ecosystem standards; research mature-project solutions when no clean best-practice fits;
  the stake-awareness rule (escalate load-bearing "mechanical" decisions); priority-balancing
  nuance.
- **Done when:** The doc specifies the decision process, the ecosystem-research move, and the
  escalation rule with the auth-class example; it is referenceable via the resolution path.
- **Dependencies:** 3
- **Citations:** D-15, D-16 · REQ-G1.1, REQ-G1.3, REQ-G1.6
- **Estimated effort:** 1 day

### Task 16 — Builder skill + core catalog + lifecycle hooks

- **Deliverables:** The builder skill: stack detection; the extensible core guard catalog
  (formatter, linter, type-checker, test runner, secret/security scan, CI gate, commit hooks)
  with breadth dimensions (docs, i18n, a11y, architecture) as growable entries; escalation of
  stake-bearing decisions into the deferral mechanism; hooks into `/spec-draft` (design phase)
  and `/execute-task` (applies guards).
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

### Task 18 — Multi-reviewer end-to-end validation run

- **Deliverables:** A full planwright pipeline run on a real work (multi-reviewer) repo (private-work-repo
  qualifies): draft → kickoff → orchestrate → execute → polish → draft PR, confirming
  Agent-resolvable surfaces for review with evidence (not auto-applied); a findings document
  covering multi-reviewer behavior, kickoff-brief effectiveness, and cross-session coordination.
- **Done when:** At least one work-project task is executed via the pipeline; the findings doc
  covers the multi-reviewer-specific behavior; the public-release gate condition (c) is met.
  Validating across a second distinct work repo is a deferred stretch (see Deferred).
- **Dependencies:** 13, 14, 16, 17
- **Citations:** D-5, D-27 · REQ-C1.3, REQ-J1.5
- **Estimated effort:** 2 days

### Task 19 — Packaging finalization & onboarding docs

- **Deliverables:** Finalized plugin manifest + `~/.claude/` writer; adopter onboarding docs
  (autopilot model, how to supply project-specific tooling/rigor without editing core docs,
  the GitHub/`gh` requirement and graceful-degradation behavior); contribution model;
  public-release readiness checklist enforcing the three gate conditions.
- **Done when:** A clean machine can install planwright both ways and resolve rule docs; the
  onboarding docs let a non-author operate the pilot-in-command model; the release checklist
  enumerates and checks the three gate conditions.
- **Dependencies:** 16, 17, 18
- **Citations:** D-24, D-29, D-35 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-K1.6, REQ-J1.5
- **Estimated effort:** 1 day

## Completed

(none yet)

## In progress

(none yet)

## Awaiting input

(none yet)

## Deferred

- **Second multi-reviewer validation repo.** Validating the pipeline across a second distinct
  work repo (beyond Task 18's first) is the user's stated ideal. **Gate:** Task 18 completed and
  a second eligible work repo is available. Citations: REQ-J1.5.
- **Purge `reference/` from main's history.** `reference/` is tracked for now so worktrees can
  access the migration source material, but it is transient and may contain personal/work data
  that must not persist in history. A deliberate human history rewrite (e.g. `git filter-repo`)
  removes it. Confidence: high. **Gate:** all `reference/`-citing tasks Completed (notably Task 3)
  AND before any public release. Citations: D-27, REQ-J1.5, REQ-J1.4 (human-reserved action, not
  an autopilot one).

## Out of scope

- **Cross-session awareness layer** (inbox/heartbeat/tmux dashboard, pair-flow REQ-F). Fast-follow
  spec; out of v1 per D-14.
- **`/peer-review`, `/code-review`, `/panel-*`, `/copilot-*`** review workflows. Fast-follows;
  v1 ships only the gate-wired review core per D-12.
- **Non-GitHub git hosts** (GitLab, Bitbucket) for the PR flow. Fast-follow per D-35.
- **The work fork and migrating the author's own dotfiles** onto planwright. Out per the seed.
