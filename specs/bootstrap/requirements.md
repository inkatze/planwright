# planwright Bootstrap — Requirements

**Status:** Draft
**Last reviewed:** 2026-06-09
**Format-version:** 1

## Goal

planwright is an autopilot for spec-driven development. The human is
pilot-in-command: they must still know how to operate the machine, and they
retain the reserved controls (sign-off and merge). Once a spec is signed off, the
framework executes it seamlessly — advancing tasks, opening draft PRs, and
converging review — without further human keystrokes. How accurately the system
flies is bounded by how good the spec is, so planwright's primary investment is
making specs as correct as possible *before any code is written*.

planwright extracts the generalizable core of the pair-flow system — the four-file
spec format, the kickoff brief as durable contract, the four-bucket finding
categorization with the solo/multi-reviewer autonomy gate, stateless step-machine
orchestration, the discovery/validation/refactor rigor, and an opinionated
engineering builder — into a standalone, opinionated Claude Code framework that any
adopter can install without inheriting the author's personal toolchain.

This is the bootstrap spec: the founding spec for building planwright v1.

## Scope

### In scope

- Versioned four-file spec format and a status-aware validator.
- Kickoff brief as durable contract (two-brief model).
- Four-bucket finding categorization with the solo/multi-reviewer autonomy gate.
- Stateless step-machine orchestration, advisory locks, one-unit-per-invocation,
  cohesion-first PR bundling.
- Test-first execution and adaptive CI retry.
- Discovery / Validation / Refactor rigor as framework doctrine.
- Opinionated engineering doctrine & builder (stake-aware quality guards).
- Accumulator taxonomy and drain policy (no write-only deferral).
- Spec lifecycle and evolution (amendment ritual, fold-vs-new).
- Composability-by-default and interaction-style rules for authoring skills.
- Packaging as a Claude Code plugin (primary) with a `~/.claude/` writer fallback.
- Operational integration (config model, hooks, conventions) on a portable runtime.

### Out of scope

- The work fork (a separate copy-and-trim effort, limited to what exists now).
- Personal-preference scaffolding (fish/mise/tmux, Ansible materialization, the
  cross-session inbox/heartbeat dashboard keyed to one tmux session per host, the
  author's specific repos). Cross-session awareness is deferred to a fast-follow.
- Auto-merge at any tier — permanent (carried invariant).
- Migrating the author's own dotfiles workflow onto planwright.
- Non-GitHub git hosts (GitLab, Bitbucket) for the PR flow — fast-follow.
- `/peer-review`, `/code-review`, `/panel-*`, `/copilot-*` review workflows —
  fast-follows; v1 ships only the gate-wired review core.

## REQ-A — Spec format, lifecycle & evolution

- **REQ-A1.1** planwright SHALL define a canonical four-file spec format
  (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) as a versioned
  meta-spec. This meta-spec is the first user-facing deliverable.
- **REQ-A1.2** `requirements.md` SHALL use stable REQ-IDs (`REQ-<Group><N>.<M>`),
  SHALL/MUST language, and a citation per requirement.
- **REQ-A1.3** `design.md` SHALL use stable D-IDs, each carrying Decision,
  Alternatives considered, and Chosen because.
- **REQ-A1.4** `tasks.md` SHALL be the canonical orchestration state record with
  the defined sections; each task SHALL carry a stable ID, Deliverables, Done when,
  Dependencies, Citations, and Estimated effort.
- **REQ-A1.5** `test-spec.md` SHALL pin every REQ to at least one verification path.
- **REQ-A1.6** `requirements.md` SHALL declare a Status of Draft, Active, or Done.
- **REQ-A1.7** Each spec bundle SHALL declare the format-version it targets; the
  validator keys its rules off that version.
- **REQ-A2.1** planwright SHALL ship a status-aware validator enforcing the
  meta-spec's structural invariants: warnings on Draft, errors (block execution) on
  Active.
- **REQ-A2.2** The validator SHALL enforce four-file presence, task structure, and
  REQ↔test-spec coverage.
- **REQ-A3.1** Status lifecycle: `/spec-draft` writes Draft; `/spec-kickoff` flips
  Draft→Active on sign-off; a spec flips Active→Done when its last task moves to
  Completed.
- **REQ-A3.2** REQ-IDs and D-IDs SHALL be stable and never reused. A changed-meaning
  requirement or decision is superseded (new ID; old marked `Superseded-by`), never
  silently rewritten.
- **REQ-A3.3** In-flight amendment is axis-driven: expression-only changes (typo,
  ambiguity, gap-fill consistent with accepted decisions) SHALL be fixed in place
  with a mandatory dated Changelog entry and no re-approval; changes that contradict
  an accepted decision or alter a REQ's meaning SHALL be superseded, with the kickoff
  brief re-synced by diff-review and scoped re-sign-off.
- **REQ-A3.4** Fold-vs-new: a new idea SHALL extend an existing bundle by default
  (append + supersede) unless a spin-new trigger fires (new external interface,
  independently ownable, orthogonal decisions, loss of comprehensibility). Bundles
  partition by functional separation.

## REQ-B — Authoring & comprehension

- **REQ-B1.1** `/spec-draft` SHALL interactively elicit the four-file bundle at
  Status Draft; it SHALL NOT commit, push, or flip a spec to Active.
- **REQ-B1.2** `/spec-draft` SHALL accept seed sources (pending notes, the
  observations/opportunities log, transcripts) and cite them.
- **REQ-B1.3** `/spec-draft` SHALL run fold-detection on every invocation regardless
  of the feature name: scan existing Active/Draft specs and, on an overlap with no
  spin-new trigger, surface an extend recommendation for the human to decide. It
  SHALL NOT auto-fold or silently obey the name over a clear overlap.
- **REQ-B1.4** `/spec-draft` SHALL mine the observations/opportunities log as a
  first-class seed source and archive/trim what it consumes.
- **REQ-B2.1** `/spec-kickoff` SHALL walk the spec section by section to mutual
  understanding, produce a signed-off `kickoff-brief.md`, and flip Draft→Active on
  sign-off.
- **REQ-B2.2** The kickoff brief SHALL be the durable contract (two-brief model:
  kickoff = contract, handover = optional cache). Its structure SHALL be specified.
- **REQ-B2.3** `/spec-kickoff` SHALL halt on genuine spec inconsistency rather than
  paper over it; the human resolves by editing the spec or recording an explicit
  override in the brief.
- **REQ-B3.1** Spec-authoring skills SHALL follow defined interaction-style rules
  (progress indicator, progressive disclosure, selectors with recommendations,
  running summary, small bites).

## REQ-C — Finding categorization & autonomy gate

- **REQ-C1.1** planwright SHALL define four finding buckets: Auto-applicable,
  Agent-resolvable, Needs sign-off, Needs human judgment.
- **REQ-C1.2** Each bucket SHALL have an explicit predicate. Agent-resolvable's
  predicate SHALL require a failing-then-passing regression test, passing project CI,
  kickoff-brief alignment, and exclusion from the hard-disqualifier zones.
- **REQ-C1.3** planwright SHALL determine repo-class (solo | multi-reviewer): in solo
  repos Agent-resolvable auto-applies; in multi-reviewer repos it surfaces for human
  review with the test + CI + alignment evidence attached.
- **REQ-C1.4** repo-class SHALL be inferred from repository signals and surfaced for
  human confirmation; it SHALL NOT be written silently. On ambiguous signals the safe
  default is multi-reviewer (do not auto-apply).
- **REQ-C1.5** Skills that act on findings locally SHALL present the four buckets as
  four tables, including empty buckets (anti-silent-pruning guard).

## REQ-D — Rigor doctrine

- **REQ-D1.1** planwright SHALL document Discovery Rigor as framework doctrine: a
  fixed lens checklist walked without silent pruning, a canonical lens-coverage table
  (empty lenses shown as none/n-a with a reason), tool-grounded discovery first,
  optional parallel lens fan-out, and a mandatory self-critique pass.
- **REQ-D1.2** planwright SHALL document Validation Rigor: three independent
  validation passes per finding (direct reproduction, orthogonal angle, outside-in),
  plus solution validation (targeted failing test, wider suite/lint/type check,
  edge/integration).
- **REQ-D1.3** planwright SHALL document Refactor Instinct: small continuous
  refactors, tool-grounded over vibes, low bar in implementation mode / high bar in
  review mode.
- **REQ-D1.4** The rigor docs SHALL be framework documentation reworded from personal
  instructions, owned by planwright (not an adopter's personal global config); skills
  SHALL reference them at runtime via a stable resolution path.
- **REQ-D2.1** planwright SHALL document the composability-by-default design principle
  (small data-in/data-out units at the logic layer; framework conventions at the
  boundary).
- **REQ-D2.2** Adopters SHALL be able to supply project-specific tooling/rigor without
  editing planwright's core rule docs.

## REQ-E — Task execution & review

- **REQ-E1.1** `/execute-task` SHALL implement one task (or a bundled set) from an
  Active spec using test-first discipline (write the failing test, confirm it fails
  for the right reason, implement to green).
- **REQ-E1.2** `/execute-task` SHALL run full project CI and apply an adaptive retry
  policy (transient → retry with backoff; logic → escalate immediately).
- **REQ-E1.3** `/execute-task` SHALL record research, performance, and security
  tradeoffs in the kickoff brief's risk register.
- **REQ-E1.4** `/execute-task` SHALL run `/polish` as a convergence step before
  opening a PR.
- **REQ-E1.5** `/execute-task` SHALL open a DRAFT PR referencing the brief, task IDs,
  REQs satisfied, and test additions.
- **REQ-E2.1** planwright SHALL provide `/self-review` (Discovery + Validation rigor
  against the feature branch) and `/polish` (autonomous loop applying Auto-applicable
  items, plus Agent-resolvable in solo repos with an active brief, local-only, until
  both action buckets are empty). Both SHALL append observations to the opportunities
  log as seed material.
- **REQ-E2.2** Skill-to-skill invocation SHALL be in-session (composition as function
  calls), not separate process launches.

## REQ-F — Orchestration

- **REQ-F1.1** `/orchestrate` SHALL be a stateless step machine: read `tasks.md`, pick
  the next ready unit, create or reuse a worktree, dispatch `/execute-task`, update
  `tasks.md`, exit. One unit (single task or one cohesion-bundle) per invocation.
- **REQ-F1.2** A ready task SHALL be one whose dependencies are all Completed and
  which is not In progress or Awaiting input.
- **REQ-F1.3** `/orchestrate` SHALL use a per-spec advisory lock held only during
  state-changing moves, with a stale-lock break threshold.
- **REQ-F1.4** `/orchestrate` SHALL refuse to act on a non-Active spec and SHALL NOT
  auto-chain into `/spec-kickoff`.
- **REQ-F1.5** `/orchestrate` SHALL halt to Awaiting input on ambiguity, missing
  dependency, test failure, hard-disqualifier, or contract drift.
- **REQ-F1.6** `/orchestrate` SHALL create draft PRs only and SHALL NOT auto-merge.
- **REQ-F1.7** `/orchestrate` SHALL bundle consecutive ready tasks only when they form
  one coherent, revertable, single-purpose deliverable (cohesion-first); combined size
  is a guardrail, not the primary signal.
- **REQ-F2.1** `/resume` SHALL be a read-only context loader (kickoff brief +
  `tasks.md` + git log + PR state + optional handover brief); it SHALL surface
  uncommitted changes and ask before proceeding.

## REQ-G — Engineering doctrine & builder

- **REQ-G1.1** planwright SHALL ship an engineering doctrine doc encoding its
  opinionated decision process: prefer framework/language/stack idioms while keeping
  domain logic composable; defer to tooling and ecosystem standards; research how
  mature projects solve a problem when no clean best-practice fits.
- **REQ-G1.2** planwright SHALL provide a builder skill that detects a project's stack
  and recommends/applies universal mechanical quality guards from a core catalog
  (formatter, linter, type-checker where applicable, test runner, secret/security
  scanning, CI quality gate, commit hooks).
- **REQ-G1.3** The builder SHALL NOT flatten complexity: decisions that appear
  mechanical but carry technical + business/domain stakes (authentication, data
  modeling, security posture, integration surface) SHALL be escalated as design
  decisions / Needs-human-judgment and routed into the deferral mechanism, never
  auto-defaulted.
- **REQ-G1.4** The builder SHALL hook into `/spec-draft` (design phase surfaces
  standards and flags stake-bearing decisions) and `/execute-task` (applies guards).
- **REQ-G1.5** The core catalog SHALL be extensible; breadth dimensions
  (documentation, internationalization, accessibility, architecture guidance) are
  catalog entries the mechanism supports and that grow over time.
- **REQ-G1.6** The doctrine SHALL support priority-balancing nuance: it advises and
  weighs tradeoffs rather than rigidly enforcing.
- **REQ-G1.7** planwright's own repository SHALL meet the quality bar its engineering
  doctrine prescribes, enforced by CI (dogfooding). The builder, once built, SHALL be
  able to reproduce/audit planwright's own guard set.

## REQ-H — Accumulator taxonomy & drain policy

- **REQ-H1.1** planwright SHALL classify every staging/accumulator surface into a named
  class with a defined drain ritual: self-draining live state (automatic),
  state-machine durable state (drained by skill/hook transitions), and
  manually-/condition-drained seed accumulators.
- **REQ-H1.2** No write-only deferral: every surface that can defer a decision or work
  SHALL have a durable home, a named reader/owner, and a re-surfacing gate or drain
  ritual.
- **REQ-H1.3** Deferrals SHALL be recorded as structured `GATE(when: …)` entries inline
  in the relevant file; condition gates are preferred over date gates; date gates SHALL
  only surface, never hard-fail.
- **REQ-H1.4** A bookkeeping drain pass SHALL evaluate open gates and re-surface
  satisfied items; it SHALL NOT auto-resolve or auto-drop. The same evaluator SHALL be
  exposed as an on-demand `/drain` move.
- **REQ-H1.5** Deferred decisions SHALL carry a confidence level so low-confidence items
  resurface first.
- **REQ-H1.6** The observations/opportunities log SHALL have a canonical reader
  (`/spec-draft`, per REQ-B1.4).

## REQ-I — Packaging, delivery & onboarding

- **REQ-I1.1** planwright SHALL be delivered primarily as a Claude Code plugin manifest;
  skills SHALL resolve their externalized rule docs (rigor, categorization, engineering
  doctrine) via a stable plugin-relative path.
- **REQ-I1.2** planwright SHALL provide a documented `~/.claude/` writer as a fallback,
  with no dependency on fish, mise, tmux, Ansible, or symlink materialization.
- **REQ-I1.3** planwright SHALL document the autopilot / pilot-in-command model so
  adopters understand the human-reserved controls (sign-off, merge).
- **REQ-I1.4** Adopters SHALL be able to supply project-specific tooling/rigor without
  editing planwright's core rule docs.
- **REQ-I1.5** planwright SHALL declare a license (MIT) and a contribution model.

## REQ-J — Invariants & release gating

- **REQ-J1.1** planwright SHALL never auto-merge at any tier (permanent).
- **REQ-J1.2** planwright SHALL never act on a non-Active spec (no bypass flag).
- **REQ-J1.3** planwright SHALL never auto-chain `/orchestrate` into `/spec-kickoff`.
- **REQ-J1.4** planwright SHALL never force-push, amend, squash, or rebase; it creates
  new commits only. All framework-created PRs are drafts.
- **REQ-J1.5** The repository SHALL start private; public release is gated on all three
  of: (a) the CLAUDE.md rules are inlined into planwright's own docs; (b) the four-file
  format meta-spec exists; (c) at least one clean multi-reviewer end-to-end run has
  completed.

## REQ-K — Operational integration

- **REQ-K1.1** planwright SHALL provide a config model: a tracked default config plus a
  local gitignored override storing per-repo settings (repo-class registry, thresholds),
  agent-maintained; repo-class entries SHALL NOT be written without human confirmation.
- **REQ-K1.2** planwright SHALL wire a PostToolUse hook that syncs `tasks.md` sections on
  `gh pr create` / `gh pr merge`, parsing the branch-naming convention.
- **REQ-K1.3** planwright SHALL wire a SessionStart tool-discovery hook that detects a
  project's linters/formatters/type-checkers and feeds Discovery Rigor and the builder.
- **REQ-K1.4** planwright SHALL define a branch-naming convention parseable by the sync
  hook and a worktree-placement convention compatible with `claude --worktree`.
- **REQ-K1.5** planwright's validator, hooks, and scripts SHALL run on a portable
  runtime (POSIX/bash) with no dependency on fish, mise, tmux, or Ansible.
- **REQ-K1.6** v1 SHALL target GitHub via the `gh` CLI for PR operations; PR-related
  operations SHALL degrade gracefully on `gh` auth failure (local work proceeds);
  non-GitHub hosts are out of v1 scope.
- **REQ-K1.7** Skills SHALL degrade gracefully on missing prerequisites (not a git repo,
  validator or `gh` absent), surfacing a clear message rather than failing opaquely.

## Sources

- `specs/_pending/notes.md` — the bootstrap seed (north star, locked decisions,
  in/out-of-scope, open questions, the accumulator-drain finding).
- `reference/pair-flow/` — the full four-file bundle + `kickoff-brief.md` being
  extracted.
- `reference/pair-flow/research/v1-retrospective.md` §4 (personal vs generalizable
  split) and §5 (what v1 did not validate).
- `reference/dotfiles-claude/CLAUDE.md` — the framework intelligence to migrate.
- `reference/dotfiles-claude/claude/{pair-flow.yml,settings.json}` and
  `reference/dotfiles-claude/specs-README.md` — config, hook wiring, format conventions.
- Drafting-session research (2026-06-08): deferred-work / drain ergonomics
  (`expiring-todo-comments`, ADR confidence levels, stale-bot critique) and living-spec
  amendment / fold practices (RFC/PEP/ADR/Kiro/Spec Kit). Cited inline in `design.md`.
- Grounding: tecpan PR #161 (Tasks 3,4,5 bundled as one cohesive deliverable) informing
  cohesion-first bundling (D-9).
