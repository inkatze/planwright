# Pair-Flow — Requirements

*A spec-driven pipeline that pairs human and agent from comprehension through execution and orchestration.*

**Status:** Active
**Cold-start next step:** Read this file end-to-end, then `design.md`, then `tasks.md` for current execution state (Completed / In progress / Forward plan).
**Last reviewed:** 2026-05-25

## Goal

A workflow where: (1) a spec is drafted with structural rigor sufficient to drive autonomous execution; (2) the human and the agent reach mutually didactic understanding of the spec before code is written; (3) execution proceeds with minimal human interruption, with the agent reproducing issues, writing regression tests, and validating against project tooling the way a human would; (4) an orchestrator advances work across the spec's task graph, opening draft PRs as tasks land; (5) the system survives session boundaries via the spec itself as the canonical state record; (6) cross-session awareness lets the human notice and respond when judgment is required.

The system is built on Claude Code primitives (skills, hooks, slash commands, scheduled remote agents, file-based state). No second agent framework is introduced.

## Glossary

- **Kickoff brief** — Signed-off `specs/{feature}/kickoff-brief.md` produced by `/spec-kickoff`. The contract every downstream skill works against.
- **Handover brief** — Optional `{worktree}/.claude/handover.md` capturing non-obvious context that doesn't fit in `tasks.md`. Cache, not source of truth.
- **Agent-resolvable** — New finding bucket for changes that are behavior-modifying but rigorously validated (failing-then-passing regression test, full CI green, kickoff-aligned, no hard disqualifier).
- **tasks.md as state** — The spec's `tasks.md` doubles as the canonical orchestration state record. Sections: Completed, In progress, Awaiting input, Deferred, Out of scope.
- **Solo repo** — A repo with no human peer reviewers beyond the spec author (e.g., tecpan, dotfiles). Permits `Agent-resolvable` to auto-apply.
- **Multi-reviewer repo** — A repo where human peer review is part of the merge gate (e.g., a work project). `Agent-resolvable` surfaces for review with evidence attached, does not auto-apply.

## REQ-A — Spec lifecycle (drafting and comprehension)

- **REQ-A1.1** The system shall provide a `/spec-draft <feature-name>` skill that elicits a spec interactively in the four-file format (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) per `Sources` below.
- **REQ-A1.2** `/spec-draft` shall extract requirements via Socratic questioning, assigning each a stable REQ-ID, SHALL/MUST language, and a citation to the framing source.
- **REQ-A1.3** `/spec-draft` shall surface design decision points where alternatives exist and record the choice as a D-ID with `Alternatives considered:` and `Chosen because:` lines.
- **REQ-A1.4** `/spec-draft` shall propose a task decomposition with stable IDs, explicit `Done when:` conditions, `Dependencies:`, and `Citations:` per task.
- **REQ-A1.5** `/spec-draft` shall pin each REQ to a verification path in `test-spec.md` (test name, `[design-level only]`, or `[manual review]` with reason).
- **REQ-A1.6** `/spec-draft` shall run the project spec validator before declaring the spec stakeholder-ready.
- **REQ-A1.7** `/spec-draft` shall use seed sources where available: `specs/_pending/notes.md`, prior recon/spike docs, or partial notes the user provides.
- **REQ-A2.1** The system shall provide a `/spec-kickoff <spec-path>` skill that produces a signed-off kickoff brief at `specs/{feature}/kickoff-brief.md`.
- **REQ-A2.2** `/spec-kickoff` shall walk the spec section by section, restating in the agent's own words, surfacing implicit domain term definitions, and pausing for human red-line per section.
- **REQ-A2.3** `/spec-kickoff` shall pose Socratic checks at each section (slicing sanity, edge cases, decision rationale) and record human responses in the brief.
- **REQ-A2.4** `/spec-kickoff` shall reconstruct the task dependency graph from `tasks.md`, identify parallelizable tasks, and flag unstated dependencies.
- **REQ-A2.5** `/spec-kickoff` shall produce a risk register listing what is underspecified, externally dependent, or could plausibly fail.
- **REQ-A2.6** The kickoff brief shall reference the spec commit hash. When any spec file changes after sign-off, only the brief sections tied to the changed content shall be invalidated and require re-signoff (section-scoped invalidation per D-27). Whole-brief invalidation applies only to wholesale spec rewrites.
- **REQ-A2.7** `/spec-kickoff` shall be invokable on existing specs (retrofit kickoff). When the spec lacks structure required for orchestration (per REQ-D5), `/spec-kickoff` shall offer to add the missing structure as part of the kickoff.
- **REQ-A2.8** When `/spec-kickoff` surfaces a genuine inconsistency between spec sections (REQs contradict, design conflicts with requirement, etc.), it shall halt without producing a brief and offer two paths: (a) edit the spec and re-run, or (b) record an explicit override in the brief explaining why the apparent inconsistency is intentional (D-42).
- **REQ-A2.9** Spec-touching skills (`/spec-draft`, `/spec-kickoff`) shall update each modified spec file's `Last reviewed:` line to the current date as a side effect of any change they make (D-40).
- **REQ-A2.10** `/spec-kickoff` shall write the brief section-by-section as each section is signed off (incremental write). A killed session leaves a partial brief that the next invocation resumes from (D-41).
- **REQ-A2.11** Kickoff briefs shall be committed to git as part of the spec bundle, not gitignored (D-49).
- **REQ-A2.12** Brief invalidation shall use the wholesale-rewrite triggers of D-51 to choose between section-scoped (default) and whole-brief invalidation paths.

## REQ-A3 — Spec status lifecycle

- **REQ-A3.1** Each spec shall declare a status in `requirements.md` header: `Draft`, `Active`, or `Done`.
- **REQ-A3.2** `/spec-draft` shall write specs with status `Draft`. `/spec-kickoff` shall flip status to `Active` on sign-off. `/orchestrate` (and the scheduled bookkeeping runner per Task 12) shall flip status to `Done` when the last task moves to `Completed` (D-31).
- **REQ-A3.3** `/execute-task` and `/orchestrate` shall refuse to act on a spec whose status is not `Active`. There is no bypass flag (D-33). Manual work outside pair-flow remains available.

## REQ-B — Task execution

- **REQ-B1.1** The system shall provide a `/execute-task <task-id>` skill that implements a single task or a bundle of tasks from a kickoff-briefed spec.
- **REQ-B1.2** `/execute-task` shall accept multiple task IDs as input and bundle them per the rule in D-11.
- **REQ-B1.3** For new behavior, `/execute-task` shall write the verifying test first per `test-spec.md`, confirm it fails for the intended reason, then implement until the test passes.
- **REQ-B1.4** For bug fixes or regressions, `/execute-task` shall reproduce the failure with a regression test first, confirm the test fails for the right reason, then fix.
- **REQ-B1.5** When research is required, `/execute-task` shall consult project docs, source code, and reputable external sources (deepwiki MCP, official docs, similar repositories, industry standards, popular projects dealing with similar issues). The agent shall weigh performance, security, and system-wide implications during this research, recording findings and tradeoffs in the kickoff brief's risk register (D-53).
- **REQ-B1.6** `/execute-task` shall run the project's full CI-equivalent (`mix ci` for Elixir, equivalent for other languages) until green before declaring implementation done.
- **REQ-B1.7** `/execute-task` shall invoke `/polish` as its final convergence step.
- **REQ-B1.8** `/execute-task` shall open a draft PR with a body that references the kickoff brief path, task IDs, REQs satisfied, and a summary of the test additions. All pair-flow-created PRs shall be drafts (D-21).
- **REQ-B1.9** When the project CI run fails, `/execute-task` shall classify the failure as transient (retry up to 2x with exponential backoff) or logic (escalate immediately to `Awaiting input`) per D-25. Unknown patterns default to logic.
- **REQ-B1.10** `/execute-task` shall assume its worktree already exists. Worktree creation is `/orchestrate`'s responsibility when invoked through the orchestrator; manual creation by the user is expected when `/execute-task` is invoked standalone (D-44).
- **REQ-B1.11** When `/execute-task` invokes `/polish` internally, it does so as a sub-step within the same Claude Code session (D-39). Hooks fire once per actual tool call. Inbox state is owned by the outer skill.

## REQ-C — Autonomous resolution

- **REQ-C1.1** The system shall introduce a new finding bucket `Agent-resolvable` to the categorization defined in user-global CLAUDE.md.
- **REQ-C1.2** A finding qualifies for `Agent-resolvable` if and only if: (a) a failing regression or behavior test exists that fails on current code for the finding's exact reason, (b) the test passes after the proposed fix, (c) full project CI passes after the fix, (d) the fix is aligned with the active kickoff brief (no contract drift), and (e) the fix is not in a hard-disqualifier zone (security primitives, migrations, public API contracts, secrets handling, CI configuration).
- **REQ-C1.3** In solo repos, `Agent-resolvable` findings shall auto-apply without human pause.
- **REQ-C1.4** In multi-reviewer repos, `Agent-resolvable` findings shall surface for human review with the failing-then-passing test, the CI output, and the kickoff alignment cited.
- **REQ-C1.5** `/polish`, `/panel-pairing`, `/peer-review`, and `/copilot-pairing` shall recognize and process the `Agent-resolvable` bucket per REQ-C1.3 and REQ-C1.4.
- **REQ-C1.6** The three existing buckets (`Auto-applicable`, `Needs sign-off`, `Needs human judgment`) shall remain unchanged in definition.

## REQ-D — Orchestration

- **REQ-D1.1** The system shall provide a `/orchestrate <spec-path>` skill that advances work on a spec by selecting the next ready task(s) and dispatching execution.
- **REQ-D2.1** `/orchestrate` shall be stateless across invocations: each call reads `tasks.md`, computes the next legal move, performs it, updates `tasks.md`, and exits.
- **REQ-D2.2** Each `/orchestrate` invocation shall pick and dispatch at most one task (or one bundle per D-11). Intra-spec parallelism is achieved by multiple invocations across separate sessions or via the scheduled runner (D-52). The per-spec lock is released before `/execute-task` runs so concurrent task execution within the same spec is allowed.
- **REQ-D3.1** `/orchestrate` shall identify ready tasks as those whose `Dependencies:` are listed in `Completed` and that are not currently in `In progress` or `Awaiting input`.
- **REQ-D4.1** `/orchestrate` shall bundle consecutive ready tasks into a single PR when the bundling rule (D-11) holds.
- **REQ-D5.1** For a spec to be orchestratable, each task shall have a stable ID, a `Done when:` condition unambiguous enough for an agent to evaluate, explicit `Dependencies:`, and `Citations:`. Repo-level configuration (`repo-class`, etc.) is supplied by `~/.claude/pair-flow.yml` and `~/.claude/pair-flow.local.yml` per D-19, not by the spec bundle. Specs missing the required task structure are not orchestratable and shall be flagged by `/orchestrate` with an offer to invoke `/spec-kickoff` in retrofit mode.
- **REQ-D6.1** `/orchestrate` shall halt after opening a draft PR. Pair-flow shall never include auto-merge functionality at any tier (D-21); all created PRs are drafts.
- **REQ-D9.1** Pair-flow skills shall discover repo configuration on first encounter by inferring `repo-class` from PR review history. The inferred value shall always be surfaced to the user for confirmation before being written. Discovery shall never silently write to `~/.claude/pair-flow.local.yml`.
- **REQ-D10.1** Cross-spec concurrent `/orchestrate` invocations in the same repo shall proceed independently. Locking is per-spec via `specs/{feature}/.orchestrate.lock` (D-37).
- **REQ-D11.1** When `/orchestrate` encounters a spec without a kickoff brief (or whose brief is fully invalidated), it shall halt cleanly and prompt the user to invoke `/spec-kickoff`. It shall not auto-chain into kickoff (D-36).
- **REQ-D12.1** Pair-flow skills shall degrade gracefully when `gh` is not authenticated: PR-related operations halt with a clear message; local-only operations proceed. `/orchestrate` mid-cycle gh failures result in an `Awaiting input` inbox entry (D-43).
- **REQ-D7.1** `/orchestrate` shall halt and post an `Awaiting input` inbox entry when it encounters: ambiguity in a task definition, an unexpected dependency, a test failure it cannot resolve, a hard-disqualifier finding, or contract drift from the kickoff brief.
- **REQ-D8.1** Multi-host or concurrent invocations against the same spec shall be coordinated via an advisory lockfile to prevent two runners from working on the same task. Lock contention shall be a clean no-op (exit with reason), not an error.

## REQ-E — Continuity across sessions

- **REQ-E1.1** `tasks.md` shall be the canonical state record for orchestration. Sections shall include `Completed`, `In progress`, `Awaiting input`, `Deferred`, and `Out of scope`.
- **REQ-E1.2** `In progress` entries shall be annotated with the current phase (e.g., `implementing`, `polish iter N`, `PR #M draft`) and last-activity timestamp.
- **REQ-E2.1** The system shall provide a `/resume` skill that loads context for a fresh session by reading the kickoff brief, the spec bundle's `tasks.md`, recent git log on the worktree branch, and any open PR state for that branch.
- **REQ-E2.2** `/resume` shall not require a handover brief to function. If one exists, `/resume` shall layer it on for non-obvious context.
- **REQ-E3.1** Skills that change task state (`/execute-task`, `/orchestrate`, hooks fired on PR open or merge) shall update `tasks.md` as a side effect.
- **REQ-E4.1** A handover brief (`{worktree}/.claude/handover.md`) may optionally be written when a session exits with in-flight work whose non-obvious context cannot be inferred from `tasks.md` + git + PR. This is an optimization, not a requirement; the system shall function correctly without it.
- **REQ-E5.1** When `/resume` opens in a worktree with uncommitted changes, it shall surface `git status` to the user and ask before proceeding. No automatic clean, commit, or stash (D-47).

## REQ-F — Cross-session awareness

- **REQ-F1.1** The system shall maintain an inbox substrate at `~/.claude/inbox/` synced across hosts via iCloud Drive or Syncthing.
- **REQ-F1.2** Each active session shall write a JSON file `{host}-{session}.json` (with `repo` and `branch` carried as JSON fields, not in the filename) describing its current state and shall refresh a `last-heartbeat` ISO timestamp every 30 seconds while alive (D-23). States: `working`, `awaiting-input`, `draft-pr-ready`, `error`, `idle`, `blocked`. Readers shall treat entries with heartbeat older than 2 minutes as stale and remove them; entries without a heartbeat field shall age out at 24 hours.
- **REQ-F2.1** The system shall provide a tmux popup (bound to `prefix + i` or equivalent) that renders the inbox as a sorted list per the D-22 visual language, with `awaiting-input` entries surfaced first.
- **REQ-F2.2** The system shall provide a tmux status bar segment that displays a count of inbox entries in `awaiting-input` state.
- **REQ-F2.3** Long-running session entries (working >30 min) shall be rendered with visual distinction in the tmux popup to surface tasks that may warrant a glance even before they transition to `awaiting-input`. Per D-22 color and sort definitions.
- **REQ-F3.1** The system shall emit macOS notifications when a session transitions into `awaiting-input` or `draft-pr-ready`.
- **REQ-F4.1** Phone push (Pushover, ntfy, etc.) is out of scope for v1. The inbox substrate shall be designed such that phone push can be layered on later without rework.

## REQ-G — Operational integration

- **REQ-G1.1** Before any panel-related changes ship, the system shall investigate why `/panel-*` skills are underused (29 copilot vs 14 panel invocations in the 30-day window ending 2026-05-21). Investigation deliverable: a written diagnosis (slowness, quota, reflex, low-yield, other) sufficient to decide whether `/panel-pairing` is retained, demoted to escalation-only, or retired.
- **REQ-G2.1** The system shall provide a PreToolUse hook that validates file paths before `Read`, `Edit`, and `Write` tool calls to address the ~82/month file-path-mistake friction. `Bash` and `NotebookEdit` are out of scope for v1 (D-26).
- **REQ-G3.1** The default backend shall be profile-aware per D-6 (work: `codex`; personal/alt: `gemini`) for `/panel-review` and `/panel-pairing`, contingent on the REQ-G1.1 investigation not surfacing a blocker.
- **REQ-G4.1** New skills shall be tracked under `roles/osx/files/claude/commands/` and propagated via the existing Ansible symlink mechanism.
- **REQ-G5.1** New hooks shall be wired from `roles/osx/files/claude/settings.json` per the conventions in the project CLAUDE.md.
- **REQ-G6.1** The system shall ship documentation updates to the project CLAUDE.md describing the new pipeline at the same level of detail as the existing `/panel-*` and `/copilot-*` sections.
- **REQ-G7.1** The spec validator (ported per D-28) shall be extended to check the D-15 task-level structural requirements (stable ID, `Done when:`, `Dependencies:`, `Citations:`). Enforcement shall be status-aware: warnings on `Draft`, errors that block `/execute-task` and `/orchestrate` on `Active` (D-45).

## Sources

- Conversation between user and Claude on 2026-05-22, this dotfiles repo.
- `/Users/inkatze/dev/tecpan/specs/README.md` — methodology source of truth for the four-file format.
- `/Users/inkatze/dev/tecpan/specs/settings/` — exemplar of the format that produces clean execution.
- `/Users/inkatze/dev/tecpan/specs/org/tasks.md` — counter-example demonstrating cost of insufficient structure.
- `/Users/inkatze/dev/tecpan/specs/validator-runs.md` — validator history.
- `~/.claude/projects/-Users-inkatze-dev-tecpan*` — JSONL transcripts mined for usage evidence.
- User-global `CLAUDE.md` — categorization, validation rigor, discovery rigor, refactor instinct rules.
