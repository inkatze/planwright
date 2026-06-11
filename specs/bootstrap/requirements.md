# planwright Bootstrap — Requirements

**Status:** Active
**Last reviewed:** 2026-06-11
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
categorization with the act-then-review autonomy gate, stateless step-machine
orchestration, the discovery/validation/refactor rigor, and an opinionated
engineering builder — into a standalone, opinionated Claude Code framework that any
adopter can install without inheriting the author's personal toolchain.

This is the bootstrap spec: the founding spec for building planwright v1.

## Scope

### In scope

- Versioned four-file spec format and a status-aware validator.
- Kickoff brief as durable contract (two-brief model).
- Four-bucket finding categorization with the act-then-review autonomy gate.
- Stateless step-machine orchestration, advisory locks, one-unit-per-step,
  control-tower dispatch, cohesion-first PR bundling.
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
  *(Cites: D-1, D-27.)*
- **REQ-A1.2** `requirements.md` SHALL use stable REQ-IDs (`REQ-<Group><N>.<M>`),
  SHALL/MUST language, and a citation per requirement.
  *(Cites: D-20; pair-flow REQ-A1.2.)*
- **REQ-A1.3** `design.md` SHALL use stable D-IDs, each carrying Decision,
  Alternatives considered, and Chosen because.
  *(Cites: D-20; pair-flow REQ-A1.3.)*
- **REQ-A1.4** `tasks.md` SHALL be the canonical orchestration state record with
  the defined sections; each task SHALL carry a stable ID, Deliverables, Done when,
  Dependencies, Citations, and Estimated effort.
  *(Cites: D-2; pair-flow REQ-D5.1.)*
- **REQ-A1.5** `test-spec.md` SHALL pin every REQ to at least one verification path.
  *(Cites: D-25; pair-flow REQ-A1.5.)*
- **REQ-A1.6** `requirements.md` SHALL declare a Status of Draft, Active, Done,
  Retired (terminal: abandoned/withdrawn, no replacement), or Superseded
  (terminal: replaced by another bundle, with a mandatory `Superseded-by:`
  pointer).
  *(Cites: D-40.)*
- **REQ-A1.7** Each spec bundle SHALL declare the format-version it targets; the
  validator keys its rules off that version.
  *(Cites: D-1.)*
- **REQ-A1.8** *(Added at polish review 2026-06-10; tightened at self-review
  2026-06-10.)* Spec directory identifiers (the `<spec>` segment used in
  `specs/<spec>/`, branch names, worktree paths, lock paths, and printed launch
  commands) SHALL match the anchored, full-string pattern `^[a-z0-9][a-z0-9-]*$`
  (substring matching is non-conforming) with a maximum length of 64; the
  validator SHALL enforce the charset and length, and no skill or hook SHALL
  interpolate an identifier that fails them into a path or command. Direct
  children of `specs/` with a leading underscore are reserved non-spec
  accumulators (`_pending/`, `_observations/`): never validated as bundles, but
  their names SHALL match `^_[a-z0-9][a-z0-9-]*$` (≤64) — exemption from bundle
  validation is not exemption from hostile-name screening — and accumulator
  *contents* used as seeds SHALL be re-validated at consumption before any
  identifier they propose is interpolated. *(Amended at delta re-walkthrough
  2026-06-11: exemption added; accumulator class closed at Amendment 5
  2026-06-11.)*
  *(Cites: brief Amendment 2, Amendment 3 (2026-06-10); delta re-walkthrough (2026-06-11).)*
- **REQ-A2.1** planwright SHALL ship a status-aware validator enforcing the
  meta-spec's structural invariants: warnings on Draft, errors (block execution) on
  Active.
  *(Cites: D-25.)*
- **REQ-A2.2** The validator SHALL enforce four-file presence, task structure, and
  REQ↔test-spec coverage.
  *(Cites: D-25.)*
- **REQ-A3.1** Status lifecycle: `/spec-draft` writes Draft; `/spec-kickoff` flips
  Draft→Active on sign-off; a spec flips Active→Done when its last Forward-plan /
  In-progress / Awaiting-input task moves to Completed. Open Deferred gates do
  not block Done; the gate evaluator SHALL continue sweeping gates in Done specs.
  Reopen cycle: extending a Done bundle flips Done→Draft; scoped kickoff of the
  delta flips back to Active. Retired and Superseded are human-set terminal
  states.
  *(Cites: D-40.)*
- **REQ-A3.2** REQ-IDs and D-IDs SHALL be stable and never reused. A changed-meaning
  requirement or decision is superseded (new ID; old marked `Superseded-by`), never
  silently rewritten.
  *(Cites: D-20.)*
- **REQ-A3.3** In-flight amendment is axis-driven: expression-only changes (typo,
  ambiguity, gap-fill consistent with accepted decisions) SHALL be fixed in place
  with a mandatory dated Changelog entry and no re-approval (re-anchoring per
  REQ-F1.10 still applies before the next dispatch); changes that contradict
  an accepted decision or alter a REQ's meaning SHALL be superseded, with the kickoff
  brief re-synced by diff-review and scoped re-sign-off. *(Amended at Amendment 5
  2026-06-11: the supersede ritual governs post-merge changes; pre-merge
  corrections on the spec's own PR amend in place with a changelog entry +
  recorded re-sign-off. Additions (new REQs, D-IDs) count as meaning-class on
  this axis; the human classifies at sign-off, recorded per REQ-F1.10.)*
  *(Cites: D-19; brief Amendment 5 (2026-06-11).)*
- **REQ-A3.4** Fold-vs-new: a new idea SHALL extend an existing bundle by default
  (append + supersede) unless a spin-new trigger fires (new external interface,
  independently ownable, orthogonal decisions, loss of comprehensibility). Bundles
  partition by functional separation.
  *(Cites: D-21, D-22.)*

## REQ-B — Authoring & comprehension

- **REQ-B1.1** `/spec-draft` SHALL interactively elicit the four-file bundle at
  Status Draft and SHALL commit the completed bundle (config opt-out:
  `commit_on_draft`); it SHALL NOT push or flip a spec to Active.
  *(Cites: D-41, D-44; pair-flow REQ-A1.1.)*
- **REQ-B1.2** `/spec-draft` SHALL accept seed sources (pending notes, the
  observations log, transcripts) and cite them.
  *(Cites: D-23; pair-flow REQ-A1.7.)*
- **REQ-B1.3** `/spec-draft` SHALL run fold-detection on every invocation regardless
  of the feature name: scan existing Active/Draft specs and, on an overlap with no
  spin-new trigger, surface an extend recommendation for the human to decide. It
  SHALL NOT auto-fold or silently obey the name over a clear overlap.
  *(Cites: D-22.)*
- **REQ-B1.4** `/spec-draft` SHALL mine the observations log as a
  first-class seed source and archive/trim what it consumes.
  *(Cites: D-23.)*
- **REQ-B2.1** `/spec-kickoff` SHALL walk the spec section by section to mutual
  understanding, produce a signed-off `kickoff-brief.md`, flip Draft→Active on
  sign-off, and commit the brief + status flip (config opt-out:
  `commit_on_kickoff`); it SHALL NOT push. **Superseded-by: REQ-B2.4**
  (2026-06-10).
- **REQ-B2.4** (supersedes REQ-B2.1) `/spec-kickoff` SHALL walk the spec section
  by section to mutual understanding, produce a signed-off `kickoff-brief.md`,
  flip Draft→Active on sign-off, commit the brief + status flip (config opt-out:
  `commit_on_kickoff`), push the spec branch, and open a DRAFT PR for the spec
  bundle. Merge of that PR (human-reserved) makes the Active spec operational
  for orchestration. It SHALL NOT mark the PR ready or merge it.
  *(Cites: D-44.)*
- **REQ-B2.2** The kickoff brief SHALL be the durable contract (two-brief model:
  kickoff = contract, handover = optional cache). Its structure SHALL be specified.
  *(Cites: D-3.)*
- **REQ-B2.3** `/spec-kickoff` SHALL halt on genuine spec inconsistency rather than
  paper over it; the human resolves by editing the spec or recording an explicit
  override in the brief.
  *(Cites: pair-flow REQ-A2.8.)*
- **REQ-B3.1** Spec-authoring skills SHALL follow defined interaction-style rules
  (progress indicator, progressive disclosure, selectors with recommendations,
  running summary, small bites).
  *(Cites: the bootstrap seed (Sources).)*
- **REQ-B3.2** Every planwright skill SHALL end with a self-healing maintenance
  check that compares its instructions against the doctrine/spec version it
  implements and writes detected drift to the observations log.
  *(Cites: D-42.)*

## REQ-C — Finding categorization & autonomy gate

- **REQ-C1.1** planwright SHALL define four finding buckets: Auto-applicable,
  Agent-resolvable, Needs sign-off, Needs human judgment.
  *(Cites: D-4.)*
- **REQ-C1.2** Each bucket SHALL have an explicit predicate. Agent-resolvable's
  predicate SHALL require a failing-then-passing regression test, passing project CI,
  kickoff-brief alignment, and exclusion from the hard-disqualifier zones.
  *(Cites: D-4; pair-flow REQ-C1.2.)*
- **REQ-C1.3** The gate SHALL be act-then-review, identical in all repos:
  Auto-applicable and Agent-resolvable findings apply with audit/evidence rows;
  Needs-sign-off findings SHALL be applied on the branch and listed in a
  pending-sign-off checklist in the draft PR description. The author's
  draft→ready flip is the universal review gate (v1 has no repo-class; nothing
  reaches reviewers before the author marks the PR ready, and any on-branch
  application is one revert from undone).
  *(Cites: D-5.)*
- **REQ-C1.4** Mid-loop hard pauses SHALL be limited to: findings or tasks in
  hard-disqualifier zones (security-sensitive code, migrations/destructive ops,
  CI configuration, lockfiles, secrets files) and irreducible
  Needs-human-judgment forks. Nothing else SHALL interrupt the loop.
  *(Cites: D-5.)*
- **REQ-C1.5** Skills that act on findings locally SHALL present the four buckets as
  four tables, including empty buckets (anti-silent-pruning guard); the tables
  are an audit record, not a decision queue.
  *(Cites: D-4.)*
- **REQ-C1.6** Declined-with-rationale SHALL be a first-class disposition: a
  validated finding may be closed with recorded reasoning in the audit table,
  re-raisable at PR review.
  *(Cites: D-5.)*
- **REQ-C1.7** Before a finding routes to Needs human judgment it SHALL climb
  the resolution ladder: kickoff-brief/spec citation, then research (REQ-D1.5),
  then project convention. Only irreducible product/priority forks queue for
  the human, surfaced at loop end with bespoke options.
  *(Cites: D-5.)*

## REQ-D — Rigor doctrine

- **REQ-D1.1** planwright SHALL document Discovery Rigor as framework doctrine: a
  fixed lens checklist walked without silent pruning, a canonical lens-coverage table
  (empty lenses shown as none/n-a with a reason), tool-grounded discovery first,
  optional parallel lens fan-out, and a mandatory self-critique pass.
  *(Cites: D-27; dotfiles CLAUDE.md (Sources).)*
- **REQ-D1.2** planwright SHALL document Validation Rigor: three independent
  validation passes per finding (direct reproduction, orthogonal angle, outside-in),
  plus solution validation (targeted failing test, wider suite/lint/type check,
  edge/integration, and an altitude check: the fix addresses cause rather than
  symptom, at the right layer).
  *(Cites: D-27; dotfiles CLAUDE.md (Sources); kickoff §2 REQ-D (2026-06-10).)*
- **REQ-D1.3** planwright SHALL document Refactor Instinct: small continuous
  refactors, tool-grounded over vibes, low bar in implementation mode / high bar in
  review mode.
  *(Cites: D-27; dotfiles CLAUDE.md (Sources).)*
- **REQ-D1.4** The rigor docs SHALL be framework documentation reworded from personal
  instructions, owned by planwright (not an adopter's personal global config); skills
  SHALL reference them at runtime via a stable resolution path.
  *(Cites: D-24.)*
- **REQ-D1.5** planwright SHALL document Research Rigor: triggers (new dependency,
  unfamiliar domain, security-touching pattern, version-sensitive API use,
  mature-project comparison), a source hierarchy (official docs, then the
  library's own source and tests, then issues/RFCs, then community posts), a
  recency discipline (current documentation over model memory), an antipattern
  check before adopting a pattern, and recording of findings in the kickoff
  brief's risk register. Wired into `/execute-task` and `/spec-draft`.
  *(Cites: kickoff §2 REQ-D (2026-06-10).)*
- **REQ-D1.6** planwright SHALL document a Security posture: write-time security
  triggers (a diff touching untrusted input, subprocess/shell construction, path
  handling, authz, crypto, or serialization gets a focused security pass before
  PR), artifact data-hygiene (no secrets, credentials, or sensitive operational
  detail in committed framework artifacts: spec bundles, briefs, risk registers,
  observation logs, PR bodies), and framework-script security (planwright's own
  hooks/scripts never execute untrusted input and guard path access).
  *(Cites: kickoff §2 REQ-D (2026-06-10).)*
- **REQ-D1.7** The rigor docs SHALL state proportionality: rigor scales with
  stake and reversibility; any skill that scopes a rigor requirement SHALL
  declare the scoping explicitly.
  *(Cites: kickoff §2 REQ-D (2026-06-10).)*
- **REQ-D2.1** planwright SHALL document the composability-by-default design principle
  (small data-in/data-out units at the logic layer; framework conventions at the
  boundary).
  *(Cites: dotfiles CLAUDE.md (Sources).)*
- **REQ-D2.2** Adopters SHALL be able to supply project-specific tooling/rigor without
  editing planwright's core rule docs.
  *(Cites: the bootstrap seed (Sources).)*

## REQ-E — Task execution & review

- **REQ-E1.1** `/execute-task` SHALL implement one task (or a bundled set) from an
  Active spec using test-first discipline (write the failing test, confirm it fails
  for the right reason, implement to green).
  *(Cites: D-11; pair-flow REQ-B1.3.)*
- **REQ-E1.2** `/execute-task` SHALL run full project CI and apply an adaptive retry
  policy (transient → retry with backoff; logic → escalate immediately).
  *(Cites: D-11; pair-flow REQ-B1.9.)*
- **REQ-E1.3** `/execute-task` SHALL record research, performance, and security
  tradeoffs in the kickoff brief's risk register.
  *(Cites: pair-flow REQ-B1.5; kickoff §2 REQ-D (2026-06-10).)*
- **REQ-E1.4** `/execute-task` SHALL run `/polish` as a convergence step before
  opening a PR.
  *(Cites: D-12; pair-flow REQ-B1.7.)*
- **REQ-E1.5** `/execute-task` SHALL open a DRAFT PR referencing the brief, task IDs,
  REQs satisfied, and test additions, and carrying the pending-sign-off
  checklist (REQ-C1.3).
  *(Cites: D-5; kickoff §2 REQ-E (2026-06-10).)*
- **REQ-E2.1** planwright SHALL provide `/self-review` (Discovery + Validation rigor
  against the feature branch) and `/polish` (autonomous act-then-review loop:
  applies Auto-applicable, Agent-resolvable, and Needs-sign-off items per
  REQ-C1.3, records declined-with-rationale dispositions, local-only, until only
  irreducible judgment forks remain). Both SHALL append observations to the
  observations log as seed material.
  *(Cites: D-5, D-12.)*
- **REQ-E2.2** Skill-to-skill invocation SHALL be in-session (composition as function
  calls), not separate process launches. Orchestrator dispatch of execution
  units (REQ-F1.8) is deliberately session-creating and is not skill
  composition.
  *(Cites: D-13.)*

## REQ-F — Orchestration

- **REQ-F1.1** `/orchestrate` SHALL be a stateless step machine: read `tasks.md`, pick
  the next ready unit, create or reuse a worktree, dispatch `/execute-task`, update
  `tasks.md`, exit the step. One unit (single task or one cohesion-bundle) per
  step; a watch loop / control tower MAY take multiple steps per session, each
  step individually atomic. *(Amended at polish review 2026-06-10; predicate
  tightened at self-review 2026-06-10.)* In-progress entries SHALL record
  dispatch metadata (backend, dispatch timestamp, worker handle/window name where
  the backend has one). The reconcile sweep SHALL first reconcile PR state (a PR
  in any state for the unit's branch takes precedence: merged → Completed, open →
  leave In progress); only then MAY it orphan a task, and only when all of: the
  entry is older than a grace threshold (default: the stale-lock threshold,
  D-10), the backend's liveness is observable from this session (subagent / tmux
  / in-session — print-backend units are exempt: their liveness is unknowable
  until a PR exists, so they age out only via the threshold plus a human
  confirm), and there is positive evidence of death (the recorded worker
  handle/window is gone, not merely unobserved). An orphaned task moves to
  Awaiting input with an orphan note; it SHALL NOT be left In progress silently
  or auto-re-dispatched.
  *(Cites: D-7, D-8, D-38.)*
- **REQ-F1.2** A ready task SHALL be one whose dependencies are all Completed and
  which is not In progress or Awaiting input. Among ready units, selection SHALL
  prefer the head of the longest dependent chain weighted by estimated effort
  (critical-path-first), FIFO on ties.
  *(Cites: pair-flow REQ-D3.1; kickoff §2 REQ-F (2026-06-10).)*
- **REQ-F1.3** `/orchestrate` SHALL use a per-spec advisory lock held only during
  state-changing moves, with a stale-lock break threshold.
  *(Cites: D-10.)*
- **REQ-F1.4** `/orchestrate` SHALL refuse to act on a non-Active spec and SHALL NOT
  auto-chain into `/spec-kickoff`.
  *(Cites: D-26.)*
- **REQ-F1.5** `/orchestrate` SHALL halt to Awaiting input on ambiguity, missing
  dependency, test failure, hard-disqualifier, or contract drift (non-exhaustive;
  pre-flight refusals — non-Active spec, missing validator (K1.7), freshness gate
  (F1.9) — are defined at their own REQs).
  *(Cites: D-38; pair-flow REQ-D7.1.)*
- **REQ-F1.6** `/orchestrate` SHALL create draft PRs only and SHALL NOT auto-merge.
  *(Cites: D-26.)*
- **REQ-F1.7** `/orchestrate` SHALL bundle consecutive ready tasks only when they form
  one coherent, revertable, single-purpose deliverable (cohesion-first); combined size
  is a guardrail, not the primary signal.
  *(Cites: D-9.)*
- **REQ-F1.8** `/orchestrate` SHALL dispatch units via configurable backends:
  background subagents (default; isolated context and worktree per unit; worker
  questions funnel back to the dispatching session), tmux windows (opt-in;
  interactive workers via `claude --worktree`; capture-pane detection only,
  never prompt impersonation), print (prepare the unit, print the launch
  command, exit), and in-session. An unattended mode (headless invocation, e.g.
  cron/CI) SHALL skip confirms and route every would-be prompt to Awaiting
  input. A shipped worker-settings profile SHALL pre-approve the routine worker
  toolset. Concurrency SHALL be capped (`max_parallel_units`, default 3). The
  dispatching session SHALL hold no in-memory state beyond the current step
  (disposable; a reconcile sweep rebuilds from `tasks.md`, `gh`, and the
  process/window list). `/orchestrate` SHALL auto-commit its `tasks.md` state
  moves (config opt-out). Worktrees SHALL be created under
  `.claude/worktrees/<branch-suffix>` (attachable via `claude --worktree`
  regardless of launch mechanism); a clean current worktree MAY be reused after
  a one-line confirm (attended only). *(Note, 2026-06-10: this REQ deliberately
  bundles the dispatch-machinery obligations as one ID; sub-clauses are pinned
  across the test-spec F1.8, F1.1, and K1.4 entries.)*
  *(Cites: D-37, D-38.)*
- **REQ-F1.9** *(Added at delta re-walkthrough 2026-06-11; amended at Amendment 5
  2026-06-11: anchor method hardened, gate mechanics pinned.)* Execution
  freshness gate. The **content anchor** is the hash of the per-file digest list
  (each file hashed with `git hash-object`, the four digests in canonical order
  — requirements, design, tasks, test-spec — hashed as a stream): boundary-safe,
  unlike hashing a bare concatenation. `tasks.md` contributes its
  task-definition content only (task headings + Deliverables / Done when /
  Dependencies / Citations / Estimated effort), per the canonical extraction the
  meta-spec defines (Task 4); orchestration-state placement and dispatch
  metadata are excluded, so `/orchestrate`'s own state moves never trip the
  gate while meaning edits always do. Until the canonical extraction ships,
  whole-file hashing is the sanctioned interim form (safe: no state moves can
  occur before the dispatch tooling exists, which transitively depends on
  Task 4). Before dispatching, `/orchestrate` (inside the D-10 lock window,
  immediately before the `tasks.md` update) and `/execute-task` (at pre-flight)
  SHALL recompute the anchor with the command recorded in the entry and compare
  it to the brief's most recent anchor entry, both read from the primary
  checkout's main view (a worker compares its worktree's spec content against
  main's brief; divergence in either direction halts). Halt conditions, all
  fail-closed to Awaiting input naming the remedy: anchor mismatch (any
  anchored content changed since the entry, committed or not → remedy:
  `/spec-kickoff` delta re-walkthrough); no anchor entry, an unparseable entry,
  a non-sanctioned computation command, or an entry from a non-sanctioned
  writer (→ remedy: complete or repair the sign-off record per REQ-F1.10).
  There is no bypass flag. These conditions apply to anchor entries recorded
  from Amendment 5 onward; earlier entries are superseded by Amendment 5's own
  anchor.
  *(Cites: D-45.)*
- **REQ-F1.10** *(Added at Amendment 5 2026-06-11.)* Sign-off record format and
  anchor validity. Every anchor entry is a machine-checkable block carrying:
  `Class:` (`meaning` or `expression-only`, on the REQ-A3.3 axis — additions
  count as meaning; the human classifies at sign-off), `Anchor:` plus the exact
  sanctioned command used (self-describing), and, for meaning-class entries, a
  `Lens-pass:` reference to the Discovery-Rigor lens review pass recorded in
  the same brief section (canonical lens-coverage table; fan-out per Discovery
  Rigor for non-trivial deltas; full bundle at first activation, delta-scoped
  at re-walkthroughs and amendments) with findings dispositioned. The anchor
  line SHALL be written last, after the sign-off record and lens-pass
  disposition, so a killed session fails closed. Writers: meaning-class entries
  SHALL be written only by `/spec-kickoff`'s sign-off flow; expression-only
  edits MAY self-re-anchor via a machine-written entry explicitly marked
  `Class: expression-only` and citing the changelog line (auditable and one
  revert from undone; misclassification is reviewable at the PR). Execution
  skills' brief writes are confined to named sections (risk register,
  observations) and SHALL never produce anchor entries. `/spec-kickoff` SHALL
  refuse to record a meaning-class anchor without a dispositioned lens pass.
  *(Cites: D-45; brief Amendment 5 (2026-06-11).)*
- **REQ-F2.1** `/resume` SHALL be a read-only context loader (kickoff brief +
  `tasks.md` + git log + PR state + optional handover brief); it SHALL surface
  uncommitted changes and ask before proceeding.
  *(Cites: D-30.)*

## REQ-G — Engineering doctrine & builder

- **REQ-G1.1** planwright SHALL ship an engineering doctrine doc encoding its
  opinionated decision process: prefer framework/language/stack idioms while keeping
  domain logic composable; defer to tooling and ecosystem standards; research how
  mature projects solve a problem when no clean best-practice fits; and a
  dependency-adoption checklist (supply chain, maintenance status, license,
  transitive weight), stake-escalated per the no-flattening rule.
  *(Cites: D-15, D-16.)*
- **REQ-G1.2** planwright SHALL provide a builder skill that detects a project's stack
  and recommends/applies universal mechanical quality guards from a core catalog
  (formatter, linter, type-checker where applicable, test runner, secret/security
  scanning, CI quality gate, commit hooks).
  *(Cites: D-15.)*
- **REQ-G1.3** The builder SHALL NOT flatten complexity: decisions that appear
  mechanical but carry technical + business/domain stakes (authentication, data
  modeling, security posture, integration surface) SHALL be escalated as design
  decisions / Needs-human-judgment and routed into the deferral mechanism, never
  auto-defaulted.
  *(Cites: D-16.)*
- **REQ-G1.4** The builder SHALL hook into `/spec-draft` (design phase surfaces
  standards and flags stake-bearing decisions), `/spec-kickoff` (flags catalogued
  decision domains the spec touches but does not decide, into the risk
  register), and `/execute-task` (applies guards).
  *(Cites: D-15, D-39.)*
- **REQ-G1.5** The core catalog SHALL be extensible; breadth dimensions
  (documentation, internationalization, accessibility, architecture guidance) are
  catalog entries the mechanism supports and that grow over time.
  *(Cites: D-39.)*
- **REQ-G1.6** The doctrine SHALL support priority-balancing nuance: it advises and
  weighs tradeoffs rather than rigidly enforcing.
  *(Cites: the bootstrap seed (Sources).)*
- **REQ-G1.7** planwright's own repository SHALL meet the quality bar its engineering
  doctrine prescribes, enforced by CI (dogfooding). The builder, once built, SHALL be
  able to reproduce/audit planwright's own guard set.
  *(Cites: D-32.)*
- **REQ-G1.8** planwright SHALL ship an extensible decision-domains catalog
  (trigger + considerations checklist + disposition rule per domain), seeded
  with approximately ten high-frequency domains (data storage & modeling,
  caching, queues/async, API surface design, authn/z, secrets & config,
  concurrency, observability, deploy/migration strategy, dependency adoption).
  Execution hitting an uncatalogued domain decision SHALL write an observation.
  *(Cites: D-39.)*

## REQ-H — Accumulator taxonomy & drain policy

- **REQ-H1.1** planwright SHALL classify every staging/accumulator surface into a named
  class with a defined drain ritual: self-draining live state (automatic),
  state-machine durable state (drained by skill/hook transitions), and
  manually-/condition-drained seed accumulators.
  *(Cites: D-18.)*
- **REQ-H1.2** No write-only deferral: every surface that can defer a decision or work
  SHALL have a durable home, a named reader/owner, and a re-surfacing gate or drain
  ritual.
  *(Cites: D-17, D-18.)*
- **REQ-H1.3** Deferrals SHALL be recorded as structured `GATE(when: …)` entries inline
  in the relevant file; condition gates are preferred over date gates; date gates SHALL
  only surface, never hard-fail. *(Amended at polish review 2026-06-10; grammar
  pinned at self-review 2026-06-10.)* Gate conditions SHALL use a closed
  declarative grammar — atoms are task-ID references, spec statuses, and ISO
  dates; the only combinator is `and` of atoms; any other condition is written as
  a free-text surface-only gate (same lane as date gates: surfaced, never
  evaluated). Productions live in the accumulator-taxonomy doctrine doc
  (Task 10). The evaluator SHALL parse by pattern match and SHALL treat gate
  content as data only: never passed to `eval`, a subshell, or arithmetic
  expansion; never used as a pattern, format string, or unquoted argument
  (`--` discipline); control characters stripped when echoed. A malformed gate
  surfaces as a drain-report-level error (the pass completes; nothing blocks)
  and is never silently skipped.
  *(Cites: D-17; brief Amendment 2, Amendment 3 (2026-06-10).)*
- **REQ-H1.4** A bookkeeping drain pass SHALL evaluate open gates and re-surface
  satisfied items; it SHALL NOT auto-resolve or auto-drop. The same evaluator SHALL be
  exposed as an on-demand `/drain` move. The pass SHALL surface the observations
  log's unmined count and oldest-entry age (surface only).
  *(Cites: D-17, D-31.)*
- **REQ-H1.5** Deferred decisions SHALL carry a confidence level so low-confidence items
  resurface first.
  *(Cites: D-17.)*
- **REQ-H1.6** The observations log SHALL have a canonical reader
  (`/spec-draft`, per REQ-B1.4).
  *(Cites: D-23.)*

## REQ-I — Packaging, delivery & onboarding

- **REQ-I1.1** planwright SHALL be delivered primarily as a Claude Code plugin manifest;
  skills SHALL resolve their externalized rule docs (rigor, categorization, engineering
  doctrine) via a stable plugin-relative path.
  *(Cites: D-24.)*
- **REQ-I1.2** planwright SHALL provide a documented `~/.claude/` writer as a fallback,
  with no dependency on fish, mise, tmux, Ansible, or symlink materialization.
  *(Cites: D-24.)*
- **REQ-I1.3** planwright SHALL document the autopilot / pilot-in-command model so
  adopters understand the human-reserved controls (sign-off, merge).
  *(Cites: D-29.)*
- **REQ-I1.4** Same requirement as REQ-D2.2, restated in the packaging group; see
  REQ-D2.2 for the normative text (adopter-supplied tooling/rigor without editing
  planwright's core rule docs). One statement, two group views.
  *(Cites: REQ-D2.2.)*
- **REQ-I1.5** planwright SHALL declare a license (MIT) and a contribution model.
  *(Cites: D-28.)*

## REQ-J — Invariants & release gating

- **REQ-J1.1** planwright SHALL never auto-merge at any tier (permanent).
  *(Cites: D-26.)*
- **REQ-J1.2** planwright SHALL never act on a non-Active spec (no bypass flag).
  *(Cites: D-26.)*
- **REQ-J1.3** planwright SHALL never auto-chain `/orchestrate` into `/spec-kickoff`.
  *(Cites: D-26.)*
- **REQ-J1.4** planwright SHALL never force-push, amend, squash, or rebase; it creates
  new commits only. All framework-created PRs are drafts.
  *(Cites: D-26.)*
- **REQ-J1.5** The repository SHALL start private; public release is gated on all three
  of: (a) the CLAUDE.md rules are inlined into planwright's own docs; (b) the four-file
  format meta-spec exists; (c) at least one clean end-to-end run on a real
  multi-contributor work repository has completed.
  *(Cites: D-27.)*

## REQ-K — Operational integration

- **REQ-K1.1** planwright SHALL provide a config model: a tracked default config plus a
  local gitignored override storing per-repo settings (thresholds, commit and
  dispatch toggles), agent-maintained; per-repo entries SHALL NOT be written
  without human confirmation.
  *(Cites: D-33.)*
- **REQ-K1.2** planwright SHALL wire a PostToolUse hook that syncs `tasks.md` sections on
  `gh pr create` / `gh pr merge`, parsing the branch-naming convention. *(Amended
  at polish review 2026-06-10; id grammar split out at self-review 2026-06-10.)*
  Before any path use, the parsed `<spec>` segment SHALL be validated against the
  REQ-A1.8 pattern and the parsed `<id>` segment against the task-id grammar
  `^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$` (per D-36: `3`, `3.5`, `3-4`); the
  resolved `tasks.md` path SHALL be containment-checked under
  `<repo-toplevel>/specs/` after canonicalization (symlink-resolved prefix
  check); a branch failing validation is a clean no-op.
  *(Cites: D-36; brief Amendment 2, Amendment 3 (2026-06-10).)*
- **REQ-K1.3** planwright SHALL wire a SessionStart tool-discovery hook that detects a
  project's linters/formatters/type-checkers and feeds Discovery Rigor and the builder.
  *(Cites: D-15; carried, dotfiles tool-discovery hook (Sources).)*
- **REQ-K1.4** planwright SHALL define a branch-naming convention parseable by the sync
  hook and a worktree-placement convention compatible with `claude --worktree`.
  *(Cites: D-36, D-37.)*
- **REQ-K1.5** planwright's validator, hooks, and scripts SHALL run on a portable
  runtime (POSIX/bash) with no dependency on fish, mise, tmux, or Ansible.
  *(Cites: D-34.)*
- **REQ-K1.6** v1 SHALL target GitHub via the `gh` CLI for PR operations; PR-related
  operations SHALL degrade gracefully on `gh` auth failure (local work proceeds);
  non-GitHub hosts are out of v1 scope.
  *(Cites: D-35.)*
- **REQ-K1.7** Skills SHALL degrade gracefully on missing prerequisites (not a git repo,
  no git remote, validator or `gh` absent), surfacing a clear message rather than
  failing opaquely. *(Amended at polish review 2026-06-10; scope refined at
  self-review 2026-06-10.)* Precedence vs REQ-A2.1: on dispatch steps
  (`/orchestrate` step execution, `/execute-task`) a missing validator is a halt
  with a clear message (fail closed — the block-execution guarantee survives);
  graceful degradation applies to authoring and read-only paths and to
  non-dispatching modes (`/orchestrate --bookkeeping`, `/drain`, `/resume`).
  *(Cites: D-35; brief Amendment 2, Amendment 3 (2026-06-10).)*
- **REQ-K1.8** Every config option SHALL be documented in a single canonical
  options reference (name, default, effect, consuming skill); planwright's own
  CI SHALL fail when an option in the tracked default config lacks a reference
  entry.
  *(Cites: D-43.)*

## Changelog

- 2026-06-10 (post-activation amendment, supersede ritual) — Spec-PR flow:
  REQ-B2.4 supersedes REQ-B2.1 (`/spec-kickoff` now pushes the spec branch and
  opens a draft PR after sign-off; merge activates the spec for orchestration).
  New D-44. Scoped re-sign-off recorded in the kickoff brief.
- 2026-06-10 — Kickoff revisions (pre-sign-off, in-place; full rationale in
  `specs/bootstrap/kickoff-brief.md`): five-status lifecycle (A1.6, A3.1);
  auto-commit (B1.1, B2.1); self-healing B3.2; act-then-review gate rewrite
  (C1.3–C1.7), repo-class removed; rigor additions (D1.2, D1.5–D1.7); execution
  updates (E1.5, E2.1, E2.2); dispatch + selection (F1.1, F1.2, F1.8);
  engineering catalog (G1.1, G1.4, G1.8); observation staleness (H1.4);
  release-gate reword (J1.5 condition (c)); config model (K1.1, K1.7, K1.8).
- 2026-06-10 (post-activation amendment, polish review; recorded in the kickoff
  brief's Amendment 2) — five hardening amendments: spec-identifier charset
  (new REQ-A1.8), sync-hook branch-segment sanitization (K1.2), gate-condition
  closed grammar (H1.3), orphaned-In-progress disposition (F1.1), validator-absent
  fail-closed precedence (K1.7). Plus I1.4 restated as a cross-reference to D2.2
  and an F1.8 deliberate-bundling note (no normative change).
- 2026-06-10 (post-activation amendment, self-review pass; Amendment 3 in the
  kickoff brief) — corrections to the polish amendments: A1.8 anchored
  full-string pattern + 64-char length bound; K1.2 task-id grammar split from
  A1.8 (dotted ids per D-36 are valid) + canonicalized containment semantics;
  H1.3 grammar productions pinned (and-of-atoms, surface-only prose lane) +
  data-only handling + malformed-gate disposition made normative; F1.1 orphan
  predicate tightened (dispatch metadata, PR-state precedence, grace threshold,
  print-backend exemption, positive evidence of death); K1.7 fail-closed scoped
  to dispatch steps; F1.2 effort-weighted selection made explicit.
- 2026-06-11 (delta re-walkthrough + Amendment 4 in the kickoff brief) —
  REQ-A3.3 pre-merge amendment class codified (Task 4 convention); REQ-A1.8
  underscore-accumulator exemption; new REQ-F1.9 execution freshness gate
  (sign-off content anchors; `/orchestrate`/`/execute-task` halt on a spec
  changed since the brief's last sign-off; D-45). Motivated by an observed
  near-miss: post-sign-off amendments could have been executed against without
  re-validation had the human not thought to ask.
- 2026-06-11 (Amendment 5 in the kickoff brief) — the lens-pass mandate plus the
  corrections its own first run produced (edits across all five files incl.
  test-spec.md): REQ-F1.9 rewritten (manifest-style boundary-safe anchor;
  tasks.md contributes definition content only; gate runs under the D-10 lock
  against the primary checkout's main view; fail-closed on absent/malformed/
  non-sanctioned entries; grandfather clause); new REQ-F1.10 (machine-checkable
  sign-off record: Class / self-describing Anchor / Lens-pass; anchor written
  last; meaning-class entries kickoff-only; expression-only marked
  self-re-anchor); A3.3 scoped (supersede = post-merge; additions are
  meaning-class; human classifies); A1.8 accumulator class closed; F1.5 marked
  non-exhaustive; D-19/D-44/D-45 annotations; Task 4/9/12/13 wiring; test-spec
  F1.9/F1.10/A1.8/A3.3 fixtures.
- 2026-06-11 (expression-only, panel review) — design.md `Last reviewed:`
  bumped 2026-06-10 → 2026-06-11 (missed at the Amendment 4–5 header sweep);
  kickoff-brief.md Amendment 3 hard-wrap repair ("history- / purge" →
  "history purge"). Self-re-anchor recorded in the kickoff brief per REQ-F1.10.
- 2026-06-11 (post-activation amendment, panel review; Amendment 6 in the
  kickoff brief, pre-merge class) — Task 19's release checklist widened to
  cover release-blocking gated Deferred entries (the `reference/` history
  purge) in addition to REQ-J1.5's three gate conditions; test-spec REQ-J1.5
  entry aligned. Closes the gap where brief Risk Register row 8 claimed T19
  enforcement the task definition did not carry.
- 2026-06-11 (post-activation amendment, self-review; Amendment 7 in the
  kickoff brief, pre-merge class) — test-spec fixture coverage completed for
  the Amendment 5 entries: F1.9 gains the fourth fail-closed halt condition
  (entry from a non-sanctioned writer); F1.10 gains the writer-side refusal
  fixture (kickoff refuses a meaning-class anchor without a dispositioned
  lens pass). No normative REQ text changed.
- 2026-06-11 (expression-only, Copilot review) — test-spec A1.8 mixed fixture
  reframed as a proposed-identifier string (a path-like input such as
  `good-name/../escape` can never exist as a single on-disk directory name;
  it is validated and refused before any directory or path is formed). No
  verification behavior changed. Self-re-anchor recorded in the kickoff brief.
- 2026-06-11 (expression-only, Copilot pairing iter 1) — test-spec H1.6 and
  I1.4 verification tags normalized to pure `[manual]` (prose moved out of the
  bracket; the entry bodies already state the joint verification), restoring
  the "tag includes [manual]" sweep convention. Self-re-anchor recorded in the
  kickoff brief.
- 2026-06-11 (expression-only, Copilot pairing iter 2) — tasks.md dependency
  graph intro reworded "generated" → "derived" (no generator tooling exists;
  the view is maintained by hand against the authoritative `Dependencies:`
  lines). Self-re-anchor recorded in the kickoff brief.
- 2026-06-11 (expression-only, Copilot pairing iter 3) — test-spec H1.3
  fixture reworded "echoed stripped" → "echoed with the control characters
  stripped", mirroring REQ-H1.3's own phrasing. Self-re-anchor recorded in
  the kickoff brief.
- 2026-06-11 (expression-only, Task 4) — per-REQ citations backfilled across
  all live requirements per the citation syntax the four-file format
  meta-spec defines (`doctrine/spec-format.md`), closing the conformance
  debt gated on Task 4 (brief Risk Register row 7). REQ-B2.1 exempt: its
  record was frozen by supersession before the citation convention applied
  (D-20, body never edited). No requirement's normative text changed.
  Self-re-anchor recorded in the kickoff brief.

## Sources

- `specs/_pending/notes.md` — the bootstrap seed (north star, locked decisions,
  in/out-of-scope, open questions, the accumulator-drain finding). Local-only:
  consumed and gitignored, so absent from clones (see `.gitignore`).
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
- Grounding: a private work repo's PR (Tasks 3,4,5 bundled as one cohesive deliverable)
  informing cohesion-first bundling (D-9).
